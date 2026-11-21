// TextSizeSliderComponent, generateMaskPath and generateKnobImage from
// DrawingUI/Sources/TextSettingsComponent.swift. Copyright Telegram Messenger. GPL v2 or later.
import AppKit

final class TelegramSizeSlider: NSView {
  var value: CGFloat = 0.5 {
    didSet {
      needsLayout = true
      setAccessibilityValue(value)
    }
  }
  var began: (() -> Void)?
  var updated: ((CGFloat) -> Void)?
  var released: (() -> Void)?
  private var tracking = false
  private let track = CAShapeLayer()
  private let knob = CALayer()
  override var isFlipped: Bool { true }
  override init(frame: CGRect) {
    super.init(frame: frame)
    wantsLayer = true
    track.fillColor = NSColor(calibratedWhite: 0x88 / 255.0, alpha: 0.3).cgColor
    layer?.addSublayer(track)
    knob.backgroundColor = NSColor.white.cgColor
    knob.cornerRadius = 16
    knob.shadowColor = NSColor.black.cgColor
    knob.shadowOffset = .zero
    knob.shadowOpacity = 0.3
    knob.shadowRadius = 9
    layer?.addSublayer(knob)
    setAccessibilityElement(true)
    setAccessibilityRole(.slider)
    setAccessibilityLabel("Size")
    setAccessibilityMinValue(0)
    setAccessibilityMaxValue(1)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layout() {
    super.layout()
    position(animated: false)
  }
  private func position(animated: Bool) {
    CATransaction.begin()
    CATransaction.setDisableActions(
      !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    CATransaction.setAnimationDuration(0.2)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
    let offset: CGFloat = tracking ? 8 : -15
    track.frame = CGRect(x: offset, y: 0, width: 30, height: bounds.height)
    let path = CGMutablePath()
    path.addArc(
      center: CGPoint(x: 15, y: 15), radius: 15, startAngle: .pi, endAngle: 0, clockwise: false)
    path.addArc(
      center: CGPoint(x: 15, y: bounds.height - 3), radius: 3, startAngle: 0, endAngle: .pi,
      clockwise: false)
    path.closeSubpath()
    track.path = path
    let y = -12 + floorToScreenPixels((bounds.height - 28) * (1 - value)) + 26
    knob.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
    knob.position = CGPoint(x: offset + 15 + (tracking ? 0 : 4), y: y)
    CATransaction.commit()
  }
  private func change(_ event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    value = 1 - max(0, min(1, (point.y - 12) / max(1, bounds.height - 24)))
    updated?(value)
  }
  override func mouseDown(with event: NSEvent) {
    tracking = true
    began?()
    change(event)
    position(animated: true)
  }
  override func mouseDragged(with event: NSEvent) { change(event) }
  override func mouseUp(with event: NSEvent) {
    tracking = false
    position(animated: true)
    released?()
  }
  private func step(_ amount: CGFloat) -> Bool {
    began?()
    value = min(1, max(0, value + amount))
    updated?(value)
    released?()
    return true
  }
  override func accessibilityPerformIncrement() -> Bool { step(0.05) }
  override func accessibilityPerformDecrement() -> Bool { step(-0.05) }
}
