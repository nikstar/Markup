import AppKit

struct ScreenshotThumbnail: Equatable {
  let window: Int
  let bounds: CGRect
  let screen: CGRect

  var onRight: Bool { bounds.midX > screen.midX }

  var panelFrame: CGRect {
    CGRect(x: bounds.minX, y: bounds.maxY + 8,
           width: bounds.width, height: (bounds.height * 2 / 3).rounded())
  }

  /// Screenshot on macOS 27 hosts its small, clickable thumbnail in a transparent
  /// display-sized window. Hit testing measures the actual thumbnail, even in portrait.
  static func locate(in screen: CGRect, window: Int, hit: (CGPoint) -> Bool) -> Self? {
    func edge(from start: CGFloat, toward end: CGFloat, inside: (CGFloat) -> Bool) -> CGFloat {
      var yes = Int(start.rounded()), no = Int(end.rounded())
      while abs(yes - no) > 1 {
        let mid = yes + (no - yes) / 2
        if inside(CGFloat(mid)) { yes = mid } else { no = mid }
      }
      return CGFloat(yes)
    }
    for right in [true, false] {
      let side = right ? screen.maxX : screen.minX
      let sign: CGFloat = right ? -1 : 1
      for dy: CGFloat in [24, 18, 48, 88, 128] {
        let y = screen.minY + dy
        for dx: CGFloat in [24, 18, 48, 88] {
          let x = side + sign * dx
          guard hit(CGPoint(x: x, y: y)) else { continue }
          let farX = side + sign * min(360, screen.width / 2)
          let farY = screen.minY + min(310, screen.height / 2)
          // The region-selection shield and the full screenshot editor can also cover this corner.
          guard !hit(CGPoint(x: farX, y: y)), !hit(CGPoint(x: x, y: farY)) else { return nil }
          let inner = edge(from: x, toward: farX) { hit(CGPoint(x: $0, y: y)) }
          let outer = edge(from: x, toward: side) { hit(CGPoint(x: $0, y: y)) }
          let center = (inner + outer) / 2
          let top = edge(from: y, toward: farY) { hit(CGPoint(x: center, y: $0)) }
          let bottom = edge(from: y, toward: screen.minY) { hit(CGPoint(x: center, y: $0)) }
          let middle = (top + bottom) / 2
          // Sample the middle, away from the two rounded corners.
          let left = edge(from: center.rounded(), toward: min(side, farX)) { hit(CGPoint(x: $0, y: middle)) }
          let last = edge(from: center.rounded(), toward: max(side, farX)) { hit(CGPoint(x: $0, y: middle)) }
          let rect = CGRect(x: left, y: bottom, width: last - left + 1, height: top - bottom + 1)
          guard max(rect.width, rect.height) >= 48 else { return nil }
          return Self(window: window, bounds: rect, screen: screen)
        }
      }
    }
    return nil
  }
}

final class ScreenshotDropPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
  let target: ImageDropTarget

  private var presented = false

  func present() {
    guard !presented else { return }
    presented = true
    if !isVisible { alphaValue = 0; orderFrontRegardless() }
    fade(to: 1)
  }

  func dismiss() {
    guard presented else { return }
    presented = false
    fade(to: 0)
  }

  private func fade(to alpha: CGFloat) {
    NSAnimationContext.runAnimationGroup { animation in
      animation.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
      animator().alphaValue = alpha
    } completionHandler: { [weak self] in
      guard let self, !presented else { return }
      orderOut(nil)
    }
  }

  init(drop: ImageDrop) {
    let rect = CGRect(x: 0, y: 0, width: 154, height: 44)
    target = ImageDropTarget(frame: rect, drop: drop)
    super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
               backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    canHide = false
    hidesOnDeactivate = false
    isExcludedFromWindowsMenu = true
    // Keep the system thumbnail clickable even if a second capture changes its size.
    level = .init(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
    let glass = NSGlassEffectView(frame: rect)
    glass.style = .regular
    glass.cornerRadius = 15
    contentView = glass
    let content = ScreenshotDropPrompt(frame: rect)
    glass.contentView = content
    content.addSubview(target)
    target.highlight = { [weak glass] active in
      glass?.tintColor = active ? .controlAccentColor : nil
    }
    setAccessibilityLabel("Drop an image to edit in Markup")
  }
}

private final class ScreenshotDropPrompt: NSView {
  private let icon = NSImageView(image: NSImage(systemSymbolName: "pencil.tip.crop.circle",
                                                accessibilityDescription: nil)!)
  private let label = NSTextField(labelWithString: "Drop to edit")
  override init(frame: CGRect) {
    super.init(frame: frame)
    icon.imageScaling = .scaleProportionallyUpOrDown
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    addSubview(icon)
    addSubview(label)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layout() {
    super.layout()
    let size = min(23, max(1, min(bounds.width, bounds.height) - 6))
    let textSize = label.intrinsicContentSize
    label.isHidden = bounds.width < size + textSize.width + 24 || bounds.height < textSize.height + 4
    let width = label.isHidden ? size : size + 8 + textSize.width
    icon.frame = CGRect(x: round(bounds.midX - width / 2), y: round(bounds.midY - size / 2),
                        width: size, height: size)
    label.frame = CGRect(origin: CGPoint(x: icon.frame.maxX + 8, y: round(bounds.midY - textSize.height / 2)),
                         size: textSize)
  }
}

/// The workspace reports the Screenshot helper's launch/exit, including background
/// launches. WindowServer is polled only during its short lifetime or an active drag.
final class ScreenshotDropMonitor {
  private let drop: ImageDrop
  private var observation: NSKeyValueObservation?
  private var timer: Timer?
  private var panel: ScreenshotDropPanel?
  private var last: ScreenshotThumbnail?
  private var dismissed: ScreenshotThumbnail?
  private var processIDs = Set<pid_t>()

  init(drop: ImageDrop) { self.drop = drop }
  func start() {
    observation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .new]) { [weak self] _, _ in
      DispatchQueue.main.async { self?.updateProcesses() }
    }
  }
  deinit { timer?.invalidate() }

  private func updateProcesses() {
    processIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screencaptureui")
      .map(\.processIdentifier))
    if timer == nil, !processIDs.isEmpty {
      let poll = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.refresh() }
      poll.tolerance = 0.025
      RunLoop.main.add(poll, forMode: .common)
      timer = poll
    }
    refresh()
  }

  private func thumbnail() -> ScreenshotThumbnail? {
    guard !processIDs.isEmpty, let primary = NSScreen.screens.first,
          let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
            as? [[String: Any]] else { return nil }
    for row in windows {
      guard let pid = row[kCGWindowOwnerPID as String] as? pid_t, processIDs.contains(pid),
            row[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.mainMenuWindow)),
            let id = row[kCGWindowNumber as String] as? Int,
            let bounds = row[kCGWindowBounds as String] as? [String: CGFloat],
            let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
      let windowFrame = CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY,
                               width: rect.width, height: rect.height)
      func hit(_ point: CGPoint) -> Bool { NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == id }
      for display in NSScreen.screens where display.frame.intersects(windowFrame) {
        if let known = last, known.window == id, known.screen == display.frame {
          let b = known.bounds
          if hit(CGPoint(x: b.midX, y: b.maxY - 2)), !hit(CGPoint(x: b.midX, y: b.maxY + 2)),
             hit(CGPoint(x: b.maxX - 2, y: b.midY)), !hit(CGPoint(x: b.maxX + 2, y: b.midY)),
             hit(CGPoint(x: b.minX + 2, y: b.midY)), !hit(CGPoint(x: b.minX - 2, y: b.midY)) {
            return known
          }
        }
        if let thumb = ScreenshotThumbnail.locate(in: display.frame, window: id, hit: hit) { return thumb }
      }
    }
    return nil
  }

  private func refresh() {
    let thumb = thumbnail()
    let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
    if let thumb {
      if dismissed?.window == thumb.window { return }
      dismissed = nil
      // Freeze the destination as soon as the user starts the drag. Screenshot
      // can move or remove its own layer before the pointer crosses our window.
      if mouseDown && panel?.isVisible == true { return }
      if panel == nil {
        let p = ScreenshotDropPanel(drop: drop)
        p.target.didDrop = { [weak self] in
          self?.dismissed = self?.last
          self?.panel?.dismiss()
        }
        panel = p
      }
      if let panel {
        // The system slides and distorts its hit region on dismissal. Resize a
        // reused host for a new aspect ratio only while the outer edge is anchored.
        let next = thumb.panelFrame, frame = panel.frame
        let edgeShift = thumb.onRight ? next.maxX - frame.maxX : next.minX - frame.minX
        let sizeChange = max(abs(frame.width - next.width), abs(frame.height - next.height))
        if last?.window != thumb.window || last?.screen != thumb.screen || last?.onRight != thumb.onRight
          || (abs(edgeShift) <= 1 && sizeChange > 4) {
          panel.setFrame(next, display: false)
        }
        panel.present()
      }
      last = thumb
    } else if !mouseDown || panel?.isVisible != true {
      panel?.dismiss()
      last = nil
      dismissed = nil
      if processIDs.isEmpty { timer?.invalidate(); timer = nil }
    }
  }
}
