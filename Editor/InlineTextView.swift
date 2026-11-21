// Native input adapter for Telegram's DrawingTextView and DrawingTextEntityView.
// Copyright Telegram Messenger. GNU GPL v2 or later.
import AppKit

final class InlineTextView: NSTextView {
  let layout: TelegramTextLayout
  let original: Annotation?
  private(set) var annotation: Annotation
  private let anchor: CGPoint
  private let imageBounds: CGRect
  private let maxWidth: CGFloat
  private let history = UndoManager()
  var onFinish: ((Bool) -> Void)?
  var onCopyEditedImage: (() -> Void)?
  var onUpdate: (() -> Void)?
  var onImagePaste: ((Data) -> Void)?
  override func paste(_ sender: Any?) {
    if string.isEmpty, let data = ImageCodec.pasteboardImage(.general), let onImagePaste {
      onImagePaste(data)
    } else {
      pasteAsPlainText(sender)
    }
  }
  var onSelectionChange: (() -> Void)?
  var selectedInk: InkColor {
    let range = selectedRange()
    if range.length > 0, range.location < layout.storage.length,
      let color = layout.storage.attribute(
        TelegramTextLayout.inkAttribute, at: range.location, effectiveRange: nil) as? NSColor
    {
      return InkColor(color)
    }
    return annotation.color
  }
  override var undoManager: UndoManager? { history }

  init(annotation: Annotation, existing: Bool, imageBounds: CGRect, zoom: CGFloat) {
    self.annotation = annotation
    original = existing ? annotation : nil
    anchor = annotation.rect.center
    self.imageBounds = imageBounds
    maxWidth = max(annotation.rect.width, floor(imageBounds.width * 0.9 / max(1, zoom)), 1)
    layout = TelegramTextLayout(annotation)
    super.init(frame: annotation.rect, textContainer: layout.container)
    isRichText = false
    importsGraphics = false
    drawsBackground = false
    isHorizontallyResizable = false
    isVerticallyResizable = false
    textContainerInset = .zero
    layout.container.widthTracksTextView = false
    layout.container.heightTracksTextView = false
    allowsUndo = true
    usesFindPanel = false
    isContinuousSpellCheckingEnabled = false
    setAccessibilityIdentifier("textEntry")
    setAccessibilityLabel("Caption")
    layout.apply(annotation)
    typingAttributes = layout.attributes
    if !existing { refit() } else { layout.setWidth(annotation.rect.width) }
    setSelectedRange(NSRange(location: layout.storage.length, length: 0))
    updateAppearance()
    NotificationCenter.default.addObserver(
      self, selector: #selector(selectionChanged),
      name: NSTextView.didChangeSelectionNotification, object: self)
  }
  @objc private func selectionChanged() { onSelectionChange?() }
  required init?(coder: NSCoder) { fatalError() }

  override func didChangeText() {
    super.didChangeText()
    annotation.text = string
    annotation.textColors = layout.colors()
    if !hasMarkedText(), string.count >= 3, let font = Self.namedFont(string),
      font != annotation.fontName
    {
      annotation.fontName = font
      layout.apply(annotation)
      typingAttributes = layout.attributes
    }
    refit()
    updateAppearance()
    onUpdate?()
  }
  // DrawingTextEntityView.availableFonts prefers an unitalicized bold member.
  private static let families = NSFontManager.shared.availableFontFamilies.reduce(
    into: [String: String]()
  ) {
    $0[$1.lowercased().replacingOccurrences(of: " ", with: "")] = $1
  }
  private static func namedFont(_ text: String) -> String? {
    guard let family = families[text.lowercased()] else { return nil }
    var preferred: String?
    for member in NSFontManager.shared.availableMembers(ofFontFamily: family) ?? [] {
      guard let name = member.first as? String else { continue }
      let lower = name.lowercased()
      if preferred == nil && (!lower.contains("-") || lower.contains("regular")) {
        preferred = name
      }
      if lower.contains("bold") && !lower.contains("italic") { preferred = name }
    }
    return preferred
  }
  private func updateAppearance() {
    insertionPointColor =
      !string.isEmpty && annotation.textStyle == .filled && annotation.color.ns.lightness > 0.99
      ? NSColor(srgbRed: 0, green: 0.533, blue: 1, alpha: 1) : .white
    alphaValue = annotation.opacity
    needsDisplay = true
  }
  private func refit() {
    let size = layout.fittedSize(
      maxWidth: maxWidth, minimumWidth: min(maxWidth, 224 * (annotation.textScale ?? 1)))
    // A new caption grows around the click. Near a screenshot edge grow inward
    // so the caret and the first line remain accessible.
    var center = anchor
    if original == nil {
      center.x = max(
        imageBounds.minX + size.width / 2, min(imageBounds.maxX - size.width / 2, center.x))
      center.y = max(
        imageBounds.minY + size.height / 2, min(imageBounds.maxY - size.height / 2, center.y))
    }
    annotation.rect = CGRect(
      x: center.x - size.width / 2, y: center.y - size.height / 2,
      width: size.width, height: size.height)
    frame = annotation.rect
  }
  func updateStyle(_ change: (inout Annotation) -> Void) {
    let range = selectedRange()
    change(&annotation)
    layout.apply(annotation)
    typingAttributes = layout.attributes
    setSelectedRange(range)
    refit()
    updateAppearance()
    onUpdate?()
  }
  func applyColor(_ ink: InkColor) {
    let range = selectedRange()
    if range.length > 0 {
      layout.storage.addAttribute(TelegramTextLayout.inkAttribute, value: ink.ns, range: range)
      let runs = layout.colors()
      updateStyle { $0.textColors = runs }
    } else {
      updateStyle {
        $0.color = ink
        $0.textColors = nil
      }
    }
  }
  private func handleEditorShortcut(_ event: NSEvent) -> Bool {
    if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
       event.charactersIgnoringModifiers?.lowercased() == "c", let onCopyEditedImage {
      onCopyEditedImage()
      return true
    }
    if !hasMarkedText(), event.modifierFlags.contains(.command), [36, 76].contains(event.keyCode) {
      onFinish?(true)
      return true
    }
    return false
  }
  override func keyDown(with event: NSEvent) {
    if !handleEditorShortcut(event) { super.keyDown(with: event) }
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    handleEditorShortcut(event) || super.performKeyEquivalent(with: event)
  }
  override func cancelOperation(_ sender: Any?) {
    if hasMarkedText() { super.cancelOperation(sender) } else { onFinish?(false) }
  }
}

final class TextEditingSurface: NSView {
  let shade = CALayer()
  private var closing = false
  private let backdrop = CaptionBackdrop(frame: .zero)
  func attach(_ text: InlineTextView, in canvas: CanvasView) {
    backdrop.canvas = canvas
    backdrop.text = text
    if backdrop.superview == nil { addSubview(backdrop) }
    addSubview(text)
    backdrop.frame = bounds
    backdrop.needsDisplay = true
  }
  func refreshBackdrop() { backdrop.needsDisplay = true }
  override var isFlipped: Bool { true }
  override init(frame: CGRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = true
    shade.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
    layer?.addSublayer(shade)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func hitTest(_ point: NSPoint) -> NSView? {
    if closing { return nil }
    let result = super.hitTest(point)
    return result === self ? nil : result
  }
  func position(in canvas: CanvasView) {
    frame = canvas.viewport
    bounds = canvas.session.file.visibleRect
    backdrop.frame = bounds
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shade.frame = bounds
    CATransaction.commit()
  }
  // UIKit moves text upright for input and restores the entity transform on Done.
  // Keep the click anchor on Mac, which has no software keyboard to accommodate.
  func animatePose(of text: InlineTextView, entering: Bool) {
    let a = text.annotation
    guard a.rotation != 0 || a.flipped else { return }
    text.wantsLayer = true
    guard let layer = text.layer else { return }
    let center = CGPoint(
      x: layer.bounds.width * (0.5 - layer.anchorPoint.x),
      y: layer.bounds.height * (0.5 - layer.anchorPoint.y))
    var pose = CATransform3DMakeTranslation(center.x, center.y, 0)
    pose = CATransform3DRotate(pose, a.rotation, 0, 0, 1)
    pose = CATransform3DScale(pose, a.flipped ? -1 : 1, 1, 1)
    pose = CATransform3DTranslate(pose, -center.x, -center.y, 0)
    let target = entering ? CATransform3DIdentity : pose
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.transform = target
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let spring = CASpringAnimation(keyPath: "transform")
      spring.mass = 1
      spring.stiffness = 240
      spring.damping = 20
      spring.duration = 0.4
      spring.fromValue = NSValue(caTransform3D: entering ? pose : CATransform3DIdentity)
      spring.toValue = NSValue(caTransform3D: target)
      layer.add(spring, forKey: "pose")
    }
    CATransaction.commit()
  }
  func dismiss(text: InlineTextView?, completion: @escaping () -> Void) {
    closing = true
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      removeFromSuperview()
      completion()
      return
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { [weak self] in
      self?.removeFromSuperview()
      completion()
    }
    if let text { animatePose(of: text, entering: false) }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = shade.presentation()?.opacity ?? 1
    fade.toValue = 0
    fade.duration = 0.3
    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    shade.opacity = 0
    shade.add(fade, forKey: "fade")
    CATransaction.commit()
  }
  func reveal() {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = 0.3
    shade.add(fade, forKey: "fade")
  }
}

private final class CaptionBackdrop: NSView {
  weak var canvas: CanvasView?
  weak var text: InlineTextView?
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func draw(_ dirtyRect: NSRect) {
    guard let canvas, var a = text?.annotation, a.textStyle == .blur, !a.text.isEmpty,
      let c = NSGraphicsContext.current?.cgContext
    else { return }
    a.rotation = 0
    a.flipped = false
    c.saveGState()
    defer { c.restoreGState() }
    let crop = canvas.session.file.visibleRect
    c.translateBy(x: -crop.minX, y: -crop.minY)
    try? canvas.renderer.drawTextBackdrop(a, file: canvas.session.file, context: c)
  }
}
