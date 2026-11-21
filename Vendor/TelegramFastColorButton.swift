// ColorSwatchComponent and ColorSpectrumPickerView, DrawingUI/ColorPickerScreen.swift.
// Copyright Telegram Messenger. GNU GPL v2 or later.
import AppKit

final class TelegramFastColorButton: NSButton {
  var color = InkColor(rgb: 0xffffff) { didSet { needsDisplay = true } }
  var began: (() -> Void)?
  var changed: ((InkColor) -> Void)?
  var ended: (() -> Void)?
  private var hold: Timer?
  private var field: TelegramColorField?
  private var reveal = CAShapeLayer()
  private let ring = Bundle(for: TelegramFastColorButton.self).url(
    forResource: "roundSpectrum", withExtension: "png"
  )
  .flatMap(NSImage.init(contentsOf:))
  override init(frame: CGRect) {
    super.init(frame: frame)
    isBordered = false
    title = ""
    toolTip = "Colors · hold and drag for the spectrum"
    setAccessibilityLabel("Colors")
    setAccessibilityIdentifier("colorPicker")
  }
  required init?(coder: NSCoder) { fatalError() }
  override func draw(_ dirtyRect: NSRect) {
    let r = CGRect(x: bounds.midX - 13, y: bounds.midY - 13, width: 26, height: 26)
    color.ns.setFill()
    NSBezierPath(ovalIn: r.insetBy(dx: 3, dy: 3)).fill()
    NSGraphicsContext.saveGraphicsState()
    let mask = NSBezierPath(ovalIn: r)
    mask.append(NSBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2)))
    mask.windingRule = .evenOdd
    mask.addClip()
    ring?.draw(in: r)
    NSGraphicsContext.restoreGraphicsState()
  }
  override func mouseDown(with event: NSEvent) {
    hold?.invalidate()
    let timer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in self?.openSpectrum() }
    RunLoop.main.add(timer, forMode: .common)
    hold = timer
  }
  private func openSpectrum() {
    guard let root = window?.contentView else { return }
    began?()
    let anchor = convert(bounds, to: root)
    let size = CGSize(width: min(350, root.bounds.width - 32), height: 296)
    let x = max(8, min(root.bounds.width - size.width - 8, anchor.minX + 5))
    let y = root.isFlipped ? anchor.maxY - size.height - 6 : anchor.minY + 6
    let field = TelegramColorField(frame: CGRect(origin: CGPoint(x: x, y: y), size: size))
    field.wantsLayer = true
    field.mode = 1
    field.color = color
    field.selected = { [weak self, weak field] ink in
      field?.color = ink
      self?.changed?(ink)
    }
    root.addSubview(field)
    self.field = field
    reveal = CAShapeLayer()
    reveal.bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
    reveal.path = CGPath(ellipseIn: reveal.bounds, transform: nil)
    reveal.position = field.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: self)
    field.layer?.mask = reveal
    scaleMask(from: 0.05, to: 3)
  }
  private func scaleMask(from: CGFloat, to: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    reveal.transform = CATransform3DMakeScale(to, to, 1)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let scale = CABasicAnimation(keyPath: "transform.scale")
      scale.fromValue = from
      scale.toValue = to
      scale.duration = 0.35
      scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      reveal.add(scale, forKey: "scale")
    }
    CATransaction.commit()
  }
  override func mouseDragged(with event: NSEvent) { field?.mouseDragged(with: event) }
  override func mouseUp(with event: NSEvent) {
    hold?.invalidate()
    hold = nil
    if let field {
      self.field = nil
      ended?()
      let filler = CALayer()
      filler.frame = field.bounds
      filler.cornerRadius = 10
      filler.backgroundColor = field.color.ns.cgColor
      field.layer?.addSublayer(filler)
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0
      fade.toValue = 1
      fade.duration = 0.25
      filler.add(fade, forKey: "fade")
      let from =
        (reveal.presentation()?.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 3
      CATransaction.begin()
      CATransaction.setCompletionBlock { [weak field] in field?.removeFromSuperview() }
      scaleMask(from: from, to: 0.06333)
      CATransaction.commit()
    } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
      _ = sendAction(action, to: target)
    }
  }
}
