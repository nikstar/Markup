// AppKit port of DrawingUI/Sources/ToolsComponent.swift (Telegram, GPL-2.0-or-later).
// Telegram brush artwork and band geometry, with fixed macOS pointer targets.
import AppKit
import QuartzCore

private let telegramToolSize = CGSize(width: 40, height: 176)

final class TelegramToolsPanel: NSView {
    var pressed: ((DrawingToolState.Key) -> Void)?
    var resized: ((DrawingToolState.Key, CGFloat) -> Void)?
    var released: (() -> Void)?
    private var tools: [TelegramToolView] = []
    private var pointerX: CGFloat?
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        for key in DrawingToolState.Key.allCases {
            let tool = TelegramToolView(type: key)
            tools.append(tool)
            addSubview(tool)
            tool.pressed = { [weak self] in self?.pressed?(key) }
            tool.swiped = { [weak self] size in self?.resized?(key, size) }
            tool.released = { [weak self] in self?.released?() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(state: DrawingState, selected: DrawingToolState.Key?, animated: Bool) {
        let animate = animated && window != nil && !isHiddenOrHasHiddenAncestor
        for tool in tools {
            tool.update(state: state.toolState(for: tool.type))
            tool.selected = tool.type == selected
            pose(tool, duration: animate ? 0.22 : 0)
        }
    }
    override func layout() {
        super.layout()
        let width = bounds.width / CGFloat(tools.count)
        for (index, tool) in tools.enumerated() {
            tool.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
            pose(tool, duration: 0)
        }
    }
    private func pose(_ tool: TelegramToolView, duration: CFTimeInterval) {
        // Fall off across one neighboring slot on each side. The hit rectangles stay still.
        let distance = pointerX.map { abs($0 - tool.frame.midX) } ?? .infinity
        let radius = max(1, tool.frame.width * 1.5)
        let weight = (1 + cos(.pi * min(distance / radius, 1))) / 2
        tool.setPose(hover: weight, duration: duration)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseMoved, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    private func track(_ x: CGFloat?) {
        guard pointerX != x else { return }
        pointerX = x
        for tool in tools { pose(tool, duration: 0.15) }
    }
    override func mouseEntered(with event: NSEvent) { track(convert(event.locationInWindow, from: nil).x) }
    override func mouseMoved(with event: NSEvent) { track(convert(event.locationInWindow, from: nil).x) }
    override func mouseExited(with event: NSEvent) { track(nil) }
    override func viewDidHide() {
        super.viewDidHide()
        pointerX = nil
        for tool in tools { pose(tool, duration: 0) }
    }
}

private final class TelegramToolView: NSView {
    let type: DrawingToolState.Key
    var selected = false {
        didSet { if selected != oldValue { setAccessibilityValue(selected ? 1 : 0) } }
    }
    var pressed: (() -> Void)?
    var swiped: ((CGFloat) -> Void)?
    var released: (() -> Void)?
    private let artwork = CALayer()
    private let shadowLayer = CALayer(), tip = CALayer(), background = CALayer(), band = CAGradientLayer()
    private var lastState: DrawingToolState?
    private var currentSize: CGFloat = 0.5
    private var initialY: CGFloat = 0
    private var previousY: CGFloat = 0
    private var dragging = false
    private var canResize = false
    private let tipImage: NSImage?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(type: DrawingToolState.Key) {
        self.type = type
        let tool = MarkupTool(type)
        let name = tool.title
        func asset(_ suffix: String) -> NSImage? {
            Bundle.main.url(forResource: "Tool" + name + suffix, withExtension: "png").flatMap(NSImage.init(contentsOf:))
        }
        tipImage = asset("Tip")
        super.init(frame: .zero)
        wantsLayer = true
        artwork.bounds = CGRect(origin: .zero, size: telegramToolSize)
        artwork.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(artwork)
        background.contents = asset("")?.cgImage
        shadowLayer.contents = asset("Shadow")?.cgImage
        tip.contents = tipImage?.cgImage
        for layer in [background, tip] {
            layer.frame = artwork.bounds
            layer.contentsGravity = .resize
        }
        shadowLayer.frame = artwork.bounds.insetBy(dx: -4, dy: 0)
        artwork.addSublayer(shadowLayer)
        if type == .pen || type == .arrow { artwork.addSublayer(background); artwork.addSublayer(tip) }
        else { artwork.addSublayer(tip); artwork.addSublayer(background) }
        band.bounds = CGRect(x: 0, y: 0, width: 34, height: 24)
        band.anchorPoint = CGPoint(x: 0.5, y: 0)
        band.position = CGPoint(x: 20, y: 64)
        band.cornerRadius = 2
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.masksToBounds = true
        if type != .eraser && type != .blur { artwork.addSublayer(band) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(name)
        setAccessibilityIdentifier("tool_" + tool.rawValue)
        toolTip = tool.shortcut.map { "\(name) (\($0.uppercased()))" } ?? name
    }
    required init?(coder: NSCoder) { fatalError() }

    func setPose(hover: CGFloat, duration: CFTimeInterval) {
        guard !bounds.isEmpty else { return }
        let scale = (selected ? 0.61 : 0.5) + hover * (selected ? 0.035 : 0.065)
        let top = bounds.height - (selected ? 72 : 55) - hover * (selected ? 4 : 8)
        let point = CGPoint(x: bounds.midX, y: top)
        guard artwork.position != point || artwork.transform.m11 != scale else { return }
        let visible = artwork.presentation() ?? artwork
        let from = visible.position
        let fromScale = visible.transform.m11
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.position = point
        artwork.transform = CATransform3DMakeScale(scale, scale, 1)
        if duration > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let lift = CABasicAnimation(keyPath: "position")
            lift.fromValue = NSValue(point: from)
            lift.toValue = NSValue(point: point)
            let zoom = CABasicAnimation(keyPath: "transform.scale")
            zoom.fromValue = fromScale
            zoom.toValue = scale
            let pose = CAAnimationGroup()
            for animation in [lift, zoom] { animation.duration = duration }
            pose.animations = [lift, zoom]
            pose.duration = duration
            pose.timingFunction = CAMediaTimingFunction(name: .easeOut)
            artwork.add(pose, forKey: "pose")
        } else { artwork.removeAnimation(forKey: "pose") }
        CATransaction.commit()
    }

    func update(state: DrawingToolState) {
        guard state != lastState else { return }
        lastState = state
        currentSize = state.size ?? 0.5
        guard let color = state.color?.toUIColor() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let tipImage {
            let image = NSImage(size: telegramToolSize, flipped: false) { rect in
                color.setFill()
                rect.fill()
                tipImage.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
                return true
            }
            tip.contents = image.cgImage
        }
        band.locations = [0, 0.15, 0.85, 1]
        band.colors = [color.withMultipliedBrightnessBy(0.7).cgColor, color.cgColor,
                       color.cgColor, color.withMultipliedBrightnessBy(0.7).cgColor]
        band.transform = CATransform3DMakeScale(1, 0.08 + 0.92 * currentSize, 1)
    }
    override func accessibilityPerformPress() -> Bool { pressed?(); return true }
    override func mouseDown(with event: NSEvent) {
        initialY = convert(event.locationInWindow, from: nil).y
        previousY = initialY
        dragging = false
        canResize = selected
    }
    override func mouseDragged(with event: NSEvent) {
        guard canResize else { return }
        let y = convert(event.locationInWindow, from: nil).y
        if abs(y - initialY) > 1 { dragging = true }
        if dragging { swiped?(max(0, min(1, currentSize - (y - previousY) / 100))) }
        previousY = y
    }
    override func mouseUp(with event: NSEvent) {
        if dragging { released?() }
        else if bounds.contains(convert(event.locationInWindow, from: nil)) { pressed?() }
        dragging = false
    }
}
