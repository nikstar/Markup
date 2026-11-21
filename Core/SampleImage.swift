import AppKit

// Deterministic image for UI tests and the self-contained preview fixture.
enum SampleImage {
  static func file() throws -> MarkupFile {
    let c = try ImageCodec.context(width: 1200, height: 760)
    c.setFillColor(NSColor(srgbRed: 0.94, green: 0.95, blue: 0.98, alpha: 1).cgColor)
    c.fill(CGRect(x: 0, y: 0, width: 1200, height: 760))
    c.setFillColor(NSColor.white.cgColor)
    c.fill(CGRect(x: 70, y: 60, width: 1060, height: 640))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    ("A little clarity goes a long way." as NSString).draw(
      at: CGPoint(x: 130, y: 135),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 46, weight: .bold), .foregroundColor: NSColor.black,
      ])
    ("A screenshot, a thought, a few good marks." as NSString).draw(
      at: CGPoint(x: 130, y: 210),
      withAttributes: [.font: NSFont.systemFont(ofSize: 25), .foregroundColor: NSColor.gray])
    for (i, color) in [NSColor.systemBlue, .systemPurple, .systemTeal].enumerated() {
      color.withAlphaComponent(0.12).setFill()
      NSBezierPath(
        roundedRect: CGRect(x: 130 + i * 320, y: 310, width: 280, height: 230), xRadius: 20,
        yRadius: 20
      ).fill()
      ("0\(i+1)" as NSString).draw(
        at: CGPoint(x: 155 + i * 320, y: 345),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: color,
        ])
      (["Capture", "Annotate", "Share"][i] as NSString).draw(
        at: CGPoint(x: 155 + i * 320, y: 440),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
          .foregroundColor: NSColor.darkGray,
        ])
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let image = c.makeImage() else { throw MarkupError.renderingFailed }
    return MarkupFile(source: try ImageCodec.encode(image, type: .png), width: 1200, height: 760)
  }
}
