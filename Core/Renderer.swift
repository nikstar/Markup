import AppKit
import CoreImage

final class MarkupRenderer {
  private var sourceData: Data?
  private var sourceImage: CGImage?
  private var blurred: CGImage?
  private var pixelated: CGImage?
  private var stickers: [Data: CGImage] = [:]
  private let sourceStrokes = TelegramStrokeRenderer()
  private let ci = CIContext(options: [.cacheIntermediates: false])

  func base(for file: MarkupFile) throws -> CGImage {
    if sourceData != file.source {
      sourceImage = try ImageCodec.decode(file.source)
      sourceData = file.source
      blurred = nil
      pixelated = nil
      stickers.removeAll()
    }
    return sourceImage!
  }
  private func filtered(_ file: MarkupFile, pixel: Bool) throws -> CGImage {
    let base = try base(for: file)
    if let cached = pixel ? pixelated : blurred { return cached }
    let image = CIImage(cgImage: base)
    let output: CIImage
    if pixel {
      output = image.applyingFilter(
        "CIPixellate", parameters: [kCIInputScaleKey: max(14, CGFloat(file.width) / 65)])
    } else {
      output = image.clampedToExtent().applyingFilter(
        "CIGaussianBlur", parameters: [kCIInputRadiusKey: max(14, CGFloat(file.width) / 80)]
      ).cropped(to: image.extent)
    }
    guard let result = ci.createCGImage(output, from: image.extent) else {
      throw MarkupError.renderingFailed
    }
    if pixel { pixelated = result } else { blurred = result }
    return result
  }
  func render(
    _ file: MarkupFile, cropped: Bool = true, maxDimension: CGFloat? = nil,
    draft: Annotation? = nil, whiteBackground: Bool = false, hiddenStrokeIDs: Set<UUID> = [], region: CGRect? = nil
  ) throws -> CGImage {
    let documentBounds = cropped ? file.visibleRect : file.imageBounds
    let bounds = region?.intersection(documentBounds) ?? documentBounds
    guard !bounds.isEmpty else { throw MarkupError.renderingFailed }
    let scale = maxDimension.map { min(1, $0 / max(bounds.width, bounds.height)) } ?? 1
    let context = try ImageCodec.context(
      width: max(1, Int((bounds.width * scale).rounded())),
      height: max(1, Int((bounds.height * scale).rounded())))
    if whiteBackground {
      context.setFillColor(NSColor.white.cgColor)
      context.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))
    }
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -bounds.minX, y: -bounds.minY)
    ImageCodec.draw(try base(for: file), in: file.imageBounds, context: context)
    // Erasers clear this isolated annotation layer, never the source screenshot.
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    sourceStrokes.retain(Set(file.annotations.map(\.id) + (draft.map { [$0.id] } ?? [])))
    let separate = file.separatesInk == true
    let visible = file.annotations.filter { !hiddenStrokeIDs.contains($0.id) }
    for a in visible where !separate || a.tool.isInk { try draw(a, file: file, in: context) }
    if let draft, (!separate || draft.tool.isInk), !hiddenStrokeIDs.contains(draft.id) {
      try draw(draft, file: file, in: context, live: true)
    }
    context.endTransparencyLayer()
    if separate {
      for a in visible where !a.tool.isInk { try draw(a, file: file, in: context) }
      if let draft, !draft.tool.isInk { try draw(draft, file: file, in: context, live: true) }
    }
    guard let image = context.makeImage() else { throw MarkupError.renderingFailed }
    return image
  }
  func isValidStroke(_ a: Annotation, size: CGSize) throws -> Bool {
    try sourceStrokes.isValid(a, size: size)
  }
  func makePenPreview(_ a: Annotation, size: CGSize) throws -> TelegramPenTool.RenderView? {
    try sourceStrokes.makePenPreview(a, size: size)
  }
  func updateStrokePreview(_ a: Annotation, size: CGSize) throws {
    try sourceStrokes.updatePreview(a, size: size)
  }
  static func smoothPath(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: first)
    if points.count == 1 {
      path.addLine(to: first.offsetBy(dx: 0.01, dy: 0))
      return path
    }
    for i in 1..<points.count {
      let mid = CGPoint.middle(p1: points[i - 1], p2: points[i])
      path.addQuadCurve(to: mid, control: points[i - 1])
    }
    path.addLine(to: points.last!)
    return path
  }
  static func shapePath(_ a: Annotation, size: CGSize = CGSize(width: 1000, height: 1000)) -> CGPath
  {
    TelegramShapeGeometry.path(a, size: size)
  }
  func draw(_ a: Annotation, file: MarkupFile, in c: CGContext, live: Bool = false) throws {
    c.saveGState()
    defer { c.restoreGState() }
    c.concatenate(a.transform)
    c.setAlpha(a.opacity)
    c.setLineWidth(a.lineWidth)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.setStrokeColor(a.color.ns.cgColor)
    c.setFillColor(a.color.ns.cgColor)
    switch a.tool {
    case .pen, .arrow, .marker, .neon, .eraser:
      try sourceStrokes.draw(a, size: file.size, live: live, context: c)
    case .blur, .pixelate:
      c.addPath(try sourceStrokes.outline(a, size: file.size, live: live))
      c.clip()
      c.concatenate(a.transform.inverted())
      ImageCodec.draw(
        try filtered(file, pixel: a.tool == .pixelate), in: file.imageBounds, context: c)
    case .line:
      guard a.points.count >= 2 else { return }
      c.addPath(TelegramVectorGeometry.path(a.telegramVector(size: file.size)))
      c.fillPath()

    case .rectangle, .ellipse, .star, .bubble, .redact:
      c.addPath(Self.shapePath(a, size: file.size))
      c.setLineWidth(TelegramShapeGeometry.lineWidth(a, size: file.size))
      c.setLineJoin(.miter)
      c.setLineCap(.butt)
      if a.tool == .redact {
        c.setAlpha(1)
        c.setFillColor(NSColor.black.cgColor)
        c.fillPath()
      } else if a.filled {
        c.fillPath()
      } else {
        c.strokePath()
      }
    case .fill:
      if a.blursCanvas == true {
        ImageCodec.draw(try filtered(file, pixel: false), in: file.imageBounds, context: c)
      } else { c.fill(file.imageBounds) }
    case .text, .sticker:
      if let data = a.imageData {
        if stickers[data] == nil { stickers[data] = try ImageCodec.decode(data) }
        ImageCodec.draw(stickers[data]!, in: a.rect, context: c)
      } else {
        try drawText(a, file: file, context: c)
      }
    case .select, .crop: break
    }
  }
  private func drawText(_ a: Annotation, file: MarkupFile, context c: CGContext) throws {
    let text = TelegramTextLayout(a)
    let layout = text.manager
    let range = layout.glyphRange(for: text.container)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    if a.textStyle == .blur { try drawTextBackdrop(a, file: file, context: c) }
    // Isolate .copy fills in the source layout manager from earlier annotations.
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    layout.drawBackground(forGlyphRange: range, at: a.rect.origin)
    layout.drawGlyphs(forGlyphRange: range, at: a.rect.origin)
    c.endTransparencyLayer()
  }
  func drawTextBackdrop(_ a: Annotation, file: MarkupFile, context c: CGContext) throws {
      let background = a.rect.insetBy(dx: -10, dy: -6)
      c.saveGState()
      defer { c.restoreGState() }
      c.addPath(CGPath(roundedRect: background, cornerWidth: 12, cornerHeight: 12, transform: nil))
      c.clip()
      c.concatenate(a.transform.inverted())
      ImageCodec.draw(try filtered(file, pixel: false), in: file.imageBounds, context: c)

  }
  func pdf(_ file: MarkupFile) throws -> Data {
    let image = try render(file)
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    guard let consumer = CGDataConsumer(data: data),
      let c = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else { throw MarkupError.renderingFailed }
    c.beginPDFPage(nil)
    c.draw(image, in: mediaBox)
    c.endPDFPage()
    c.closePDF()
    return data as Data
  }
  static func hit(
    _ a: Annotation, point: CGPoint, tolerance: CGFloat,
    size: CGSize = CGSize(width: 1000, height: 1000)
  ) -> Bool {
    let p = point.applying(a.transform.inverted())
    if a.tool.isBrush || a.tool == .line {
      let path =
        a.tool == .line && a.points.count == 3
        ? CGPath.curve(
          start: a.points[0], end: a.points[2], mid: a.points[1], lineWidth: nil, arrowSize: nil)
        : smoothPath(a.points)
      return path.copy(
        strokingWithWidth: max(a.lineWidth * 3, tolerance * 2), lineCap: .round, lineJoin: .round,
        miterLimit: 10
      ).contains(p)
    }
    if a.tool.isVector && !a.filled && a.tool != .redact {
      return shapePath(a, size: size).copy(
        strokingWithWidth: max(a.lineWidth, tolerance * 2), lineCap: .round, lineJoin: .round,
        miterLimit: 10
      ).contains(p)
    }
    return a.rawBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
  }
}
