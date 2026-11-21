// Adapted from DrawingUI/Sources/EyedropperView.swift. Copyright Telegram Messenger. GPL v2 or later.
import AppKit

final class EyedropperView: NSView {
  private let image: CGImage
  private let bytes: CFData
  private unowned let canvas: CanvasView
  private let lens = CALayer()
  private(set) var pixel = CGPoint.zero
  var completed: ((InkColor?) -> Void)?
  private var closing = false
  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { true }

  init(canvas: CanvasView, image: CGImage) throws {
    guard image.bitsPerPixel == 32, let bytes = image.dataProvider?.data else {
      throw MarkupError.renderingFailed
    }
    self.canvas = canvas
    self.image = image
    self.bytes = bytes
    super.init(frame: canvas.bounds)
    autoresizingMask = [.width, .height]
    wantsLayer = true
    lens.bounds = CGRect(x: 0, y: 0, width: 148, height: 148)
    lens.shadowColor = NSColor.black.cgColor
    lens.shadowOpacity = 0.65
    lens.shadowRadius = 20
    lens.shadowOffset = .zero
    lens.shadowPath = CGPath(ellipseIn: lens.bounds, transform: nil)
    layer?.addSublayer(lens)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("Sample image color")
    update(at: canvas.viewPoint(canvas.insertionCenter))
  }
  required init?(coder: NSCoder) { fatalError() }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.inVisibleRect, .mouseMoved, .activeInKeyWindow], owner: self))
  }
  override func draw(_ dirtyRect: NSRect) {
    if let c = NSGraphicsContext.current?.cgContext {
      ImageCodec.draw(image, in: canvas.viewport, context: c)
    }
  }
  var color: InkColor {
    let ptr = CFDataGetBytePtr(bytes)! + Int(pixel.y) * image.bytesPerRow + Int(pixel.x) * 4
    let alpha = Double(ptr[3])
    if alpha == 0 { return .clear }
    return InkColor(
      Double(ptr[0]) / alpha, Double(ptr[1]) / alpha, Double(ptr[2]) / alpha, alpha / 255)
  }
  func update(at location: CGPoint) {
    let crop = canvas.session.file.visibleRect
    let p = canvas.imagePoint(location) - crop.origin
    pixel = CGPoint(
      x: min(CGFloat(image.width - 1), max(0, floor(p.x))),
      y: min(CGFloat(image.height - 1), max(0, floor(p.y))))
    let ink = color.ns
    let bounds = lens.bounds
    let rasterScale = canvas.backingScale
    guard
      let c = try? ImageCodec.context(width: Int(148 * rasterScale), height: Int(148 * rasterScale))
    else { return }
    c.scaleBy(x: rasterScale, y: rasterScale)
    c.setFillColor(ink.cgColor)
    c.fillEllipse(in: bounds)
    c.setFillColor((ink.lightness > 0.9 ? NSColor(rgb: 0x999999) : .white).cgColor)
    c.fillEllipse(in: bounds.insetBy(dx: 12, dy: 12))
    let clip = bounds.insetBy(dx: 17, dy: 17)
    c.addEllipse(in: clip)
    c.clip()
    c.interpolationQuality = .none
    let sample = CGRect(x: pixel.x - 4, y: pixel.y - 4, width: 9, height: 9)
      .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    if let pixels = image.cropping(to: sample) {
      ImageCodec.draw(
        pixels,
        in: CGRect(
          x: 74 + (sample.minX - pixel.x - 0.5) * 15,
          y: 74 + (sample.minY - pixel.y - 0.5) * 15,
          width: sample.width * 15, height: sample.height * 15), context: c)
    }
    c.setFillColor(
      (ink.lightness > 0.9 ? NSColor(rgb: 0x505050) : .white).withAlphaComponent(0.6).cgColor)
    for i in 0..<8 {
      let offset = CGFloat(24 + i * 14)
      c.fill(CGRect(x: offset, y: 17, width: 1, height: 114))
      c.fill(CGRect(x: 17, y: offset, width: 114, height: 1))
    }
    c.setStrokeColor(NSColor.white.cgColor)
    c.setLineWidth(4)
    c.stroke(CGRect(x: 65.5, y: 65.5, width: 17, height: 17))
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    lens.position = canvas.viewPoint(pixel + crop.origin + CGPoint(x: 0.5, y: 0.5))
    lens.contents = c.makeImage()
    CATransaction.commit()
  }
  func appear() {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    let spring = CASpringAnimation(keyPath: "transform.scale")
    spring.fromValue = 0.01
    spring.toValue = 1
    spring.mass = 1
    spring.damping = 20
    spring.stiffness = 240
    spring.duration = 0.4
    lens.add(spring, forKey: "scale")
    fade(from: 0, to: 1)
  }
  private func fade(from: Float, to: Float) {
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = from
    fade.toValue = to
    fade.duration = 0.2
    lens.add(fade, forKey: "fade")
  }
  func finish(_ apply: Bool) {
    guard !closing else { return }
    closing = true
    completed?(apply ? color : nil)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { [weak self] in self?.removeFromSuperview() }
    lens.opacity = 0
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      fade(from: 1, to: 0)
      let shrink = CABasicAnimation(keyPath: "transform.scale")
      shrink.fromValue = 1
      shrink.toValue = 0.01
      shrink.duration = 0.2
      lens.add(shrink, forKey: "scale")
    }
    CATransaction.commit()
  }
  override func hitTest(_ point: NSPoint) -> NSView? { closing ? nil : super.hitTest(point) }
  override func resetCursorRects() {
    super.resetCursorRects()
    addCursorRect(bounds, cursor: .crosshair)
  }
  override func mouseMoved(with event: NSEvent) {
    if !closing { update(at: convert(event.locationInWindow, from: nil)) }
  }
  override func mouseDown(with event: NSEvent) { mouseMoved(with: event) }
  override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    update(at: point)
    finish(canvas.viewport.contains(point))
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      finish(false)
    } else if event.keyCode == 36 {
      finish(true)
    } else {
      super.keyDown(with: event)
    }
  }
}
