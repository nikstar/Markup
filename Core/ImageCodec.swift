import AppKit
import ImageIO
import UniformTypeIdentifiers

// All editor coordinates are image pixels, with the origin at the top left.
enum ImageCodec {
  static func decode(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let w = props[kCGImagePropertyPixelWidth] as? Int,
      let h = props[kCGImagePropertyPixelHeight] as? Int
    else { throw MarkupError.invalidImage }
    guard w > 0, h > 0, w <= 16384, h <= 16384, Double(w) * Double(h) <= 80_000_000 else {
      throw MarkupError.tooLarge
    }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(w, h),
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
      throw MarkupError.invalidImage
    }
    return image
  }
  static func encode(_ image: CGImage, type: UTType) throws -> Data {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
    else { throw MarkupError.renderingFailed }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw MarkupError.renderingFailed }
    return data as Data
  }
  static func context(width: Int, height: Int) throws -> CGContext {
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw MarkupError.renderingFailed }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    return context
  }
  static func draw(_ image: CGImage, in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
  }
  static func pasteboardImage(_ board: NSPasteboard) -> Data? {
    for type in [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType("com.apple.png-sticker"), .tiff] {
      if let d = board.data(forType: type) { return d }
    }
    if let image = NSImage(pasteboard: board) { return image.tiffRepresentation }
    return nil
  }
}
