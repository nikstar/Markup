import AppKit
import QuartzCore

/// AppKit adaptation of nikstar/VariableBlur. Each strip samples the live canvas behind the
/// controls. The drawing surface itself stays unfiltered, including its transparent margins.
final class CanvasToolbarBlur {
  private let top = Strip(atTop: true)
  private let bottom = Strip(atTop: false)

  func update(layer: CALayer, editing: CGRect, image: CGRect, scale: CGFloat) {
    let bounds = layer.bounds
    let upper = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                       height: max(0, editing.minY - bounds.minY))
    let lower = CGRect(x: bounds.minX, y: editing.maxY, width: bounds.width,
                       height: max(0, bounds.maxY - editing.maxY))
    top.update(in: layer, band: upper, image: image, scale: scale)
    bottom.update(in: layer, band: lower, image: image, scale: scale)
  }

  func updateColors(in appearance: NSAppearance) {
    appearance.performAsCurrentDrawingAppearance {
      let color = NSColor.windowBackgroundColor
      top.setTint(color)
      bottom.setTint(color)
    }
  }

  private final class Strip {
    let atTop: Bool
    let clip = CALayer()
    private let backdrop: CALayer?
    private let filter: NSObject?
    private let tint = CAGradientLayer()
    private var previousHeight: CGFloat = 0
    private var previousScale: CGFloat = 0

    init(atTop: Bool) {
      self.atTop = atTop
      backdrop = (NSClassFromString("CABackdropLayer") as? CALayer.Type)?.init()
      let factory = NSSelectorFromString("filterWithType:")
      if let type = NSClassFromString("CAFilter") as? NSObject.Type, type.responds(to: factory) {
        filter = type.perform(factory, with: "variableBlur")?.takeUnretainedValue() as? NSObject
      } else { filter = nil }
      filter?.setValue(32.0, forKey: "inputRadius")
      filter?.setValue(true, forKey: "inputNormalizeEdges")
      clip.name = atTop ? "Title bar blur" : "Tool shelf blur"
      clip.masksToBounds = true
      // Canvas overlays (live ink, selection and the text view) also belong behind these strips.
      clip.zPosition = 1
      if let backdrop { clip.addSublayer(backdrop) }
      tint.startPoint = CGPoint(x: 0.5, y: atTop ? 1 : 0)
      tint.endPoint = CGPoint(x: 0.5, y: atTop ? 0 : 1)
      setTint(.windowBackgroundColor)
      clip.addSublayer(tint)
    }

    func setTint(_ color: NSColor) {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      let muted = color.withAlphaComponent(0.45).cgColor
      tint.colors = [color.withAlphaComponent(0).cgColor, muted, muted]
      CATransaction.commit()
    }

    func update(in layer: CALayer, band: CGRect, image: CGRect, scale: CGFloat) {
      let overlap = band.intersection(image)
      guard !overlap.isEmpty else {
        if clip.superlayer != nil { clip.removeFromSuperlayer() }
        return
      }
      // Keep the gradient at a fixed position in the window even during a partial overlap.
      let local = band.offsetBy(dx: -overlap.minX, dy: -overlap.minY)
      guard clip.superlayer == nil || clip.frame != overlap || tint.frame != local || scale != previousScale else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      defer { CATransaction.commit() }
      if clip.superlayer == nil { layer.addSublayer(clip) }
      clip.frame = overlap
      backdrop?.frame = local
      tint.frame = local
      guard band.height != previousHeight || scale != previousScale else { return }
      previousHeight = band.height
      previousScale = scale
      let ramp = min(band.height, atTop ? 40 : 64)
      tint.locations = [0, NSNumber(value: Double(ramp / band.height)), 1]
      let height = max(1, Int(ceil(band.height * scale)))
      var rgba = [UInt8](repeating: 0, count: height * 4)
      for row in 0..<height {
        let y = (CGFloat(row) + 0.5) * band.height / CGFloat(height)
        let t = min(1, (atTop ? band.height - y : y) / ramp)
        let alpha = UInt8((255 * t * t * t).rounded())
        for channel in 0..<4 { rgba[row * 4 + channel] = alpha }
      }
      if let provider = CGDataProvider(data: Data(rgba) as CFData),
         let mask = CGImage(width: 1, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
        filter?.setValue(mask, forKey: "inputMaskImage")
        backdrop?.setValue(scale, forKey: "scale")
        backdrop?.filters = filter.map { [$0] }
      }
    }
  }
}
