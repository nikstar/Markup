import AppKit

extension MarkupTool {
  var telegramKey: DrawingToolState.Key? {
    switch self {
    case .pen: return .pen
    case .arrow: return .arrow
    case .marker: return .marker
    case .neon: return .neon
    case .blur: return .blur
    case .eraser: return .eraser
    default: return nil
    }
  }
  init(_ key: DrawingToolState.Key) {
    switch key {
    case .pen: self = .pen
    case .arrow: self = .arrow
    case .marker: self = .marker
    case .neon: self = .neon
    case .blur: self = .blur
    case .eraser: self = .eraser
    }
  }
}
enum TelegramBrushMetrics {
  static func range(_ tool: MarkupTool, size: CGSize) -> ClosedRange<CGFloat> {
    let maxSide = max(size.width, size.height)
    if tool == .marker { return max(10, maxSide * 0.01)...max(20, maxSide * 0.09) }
    return max(1, maxSide * 0.002)...max(10, maxSide * 0.07)
  }
  static func width(_ tool: MarkupTool, size: CGSize, value: CGFloat) -> CGFloat {
    let r = range(tool, size: size)
    return r.lowerBound + (r.upperBound - r.lowerBound) * value
  }
  static func value(_ tool: MarkupTool, size: CGSize, width: CGFloat) -> CGFloat {
    let r = range(tool, size: size)
    return (width - r.lowerBound) / (r.upperBound - r.lowerBound)
  }
}

final class TelegramStrokeRenderer {
  private final class Stroke {
    let signature: Annotation
    let size: CGSize
    let pen: TelegramPenTool?
    let neon: TelegramNeonTool?
    let marker: TelegramMarkerRenderer?
    let markerTool: TelegramMarkerTool?
    var samples: [CGPoint] = []
    var sampleVelocities: [CGFloat] = []
    var finished = false
    var image: CGImage?
    init(_ a: Annotation, size: CGSize) throws {
      self.signature = TelegramStrokeRenderer.signature(a)
      self.size = size
      let value = a.brushSize ?? TelegramBrushMetrics.value(a.tool, size: size, width: a.lineWidth)
      let color = a.color.withUpdatedAlpha(CGFloat(a.color.alpha) * a.opacity)
      if a.tool == .marker {
        marker = try TelegramMarkerRenderer(size: size)
        markerTool = TelegramMarkerTool(drawingSize: size, color: color, lineWidth: value)
        markerTool?.metalView = marker
        pen = nil
        neon = nil
      } else if a.tool == .neon {
        neon = TelegramNeonTool(drawingSize: size, color: color, lineWidth: value)
        pen = nil
        marker = nil
        markerTool = nil
      } else {
        pen = TelegramPenTool(
          drawingSize: size, color: color, lineWidth: value, hasArrow: a.tool == .arrow,
          isEraser: a.tool == .eraser, isBlur: a.tool == .blur || a.tool == .pixelate,
          blurredImage: nil, animationsEnabled: true)
        neon = nil
        marker = nil
        markerTool = nil
      }
    }
    func update(_ a: Annotation, live: Bool) throws {
      let changed = samples.count != a.points.count || (!live && !finished)
      for i in samples.count..<a.points.count {
        let point = DrawingPoint(
          location: a.points[i],
          velocity: a.velocities?.indices.contains(i) == true ? a.velocities![i] : 1000)
        // The final new sample is .ended, not .changed followed by a duplicate
        // .ended. Marker stamp overlap and pen width history depend on this.
        let state: DrawingGesturePipeline.DrawingGestureState =
          i == 0
          ? .began
          : (!live && a.hasTerminalSample == true && i == a.points.count - 1 ? .ended : .changed)
        pen?.updatePath(point, state: state, zoomScale: a.inputZoom ?? 1)
        neon?.updatePath(point, state: state, zoomScale: a.inputZoom ?? 1)
        markerTool?.updatePath(point, state: state, zoomScale: a.inputZoom ?? 1)
        if state == .ended { finished = true }
      }
      samples = a.points
      sampleVelocities = a.points.indices.map {
        a.velocities?.indices.contains($0) == true ? a.velocities![$0] : 1000
      }
      if !live && !finished, let p = a.points.last {
        let point = DrawingPoint(location: p, velocity: a.velocities?.last ?? 1000)
        pen?.updatePath(point, state: .ended, zoomScale: a.inputZoom ?? 1)
        neon?.updatePath(point, state: .ended, zoomScale: a.inputZoom ?? 1)
        markerTool?.updatePath(point, state: .ended, zoomScale: a.inputZoom ?? 1)
        finished = true
      }
      if let marker { if image == nil || changed { image = try marker.image() } }
    }
  }
  private var cache: [UUID: Stroke] = [:]
  private static func signature(_ a: Annotation) -> Annotation {
    var s = a
    s.points = []
    s.pressures = []
    s.velocities = nil
    s.hasTerminalSample = nil
    s.rect = .zero
    s.rotation = 0
    s.flipped = false
    return s
  }
  private func stroke(_ a: Annotation, size: CGSize, live: Bool) throws -> Stroke {
    let sig = Self.signature(a)
    let velocities = a.points.indices.map {
      a.velocities?.indices.contains($0) == true ? a.velocities![$0] : 1000
    }
    if let old = cache[a.id],
      old.signature != sig || old.size != size || old.samples.count > a.points.count
        || !a.points.starts(with: old.samples) || !velocities.starts(with: old.sampleVelocities)
        || (live && old.finished)
    {
      cache[a.id] = nil
    }
    if cache[a.id] == nil {
      // Finished marker images can be recreated; bound the GPU texture cache.
      if a.tool == .marker { cache = cache.filter { $0.value.marker == nil } }
      cache[a.id] = try Stroke(a, size: size)
    }
    let result = cache[a.id]!
    try result.update(a, live: live)
    return result
  }
  func outline(_ a: Annotation, size: CGSize, live: Bool) throws -> CGPath {
    try stroke(a, size: size, live: live).pen?.outline ?? CGMutablePath()
  }
  func draw(_ a: Annotation, size: CGSize, live: Bool, context: CGContext) throws {
    let s = try stroke(a, size: size, live: live)
    if let image = s.image {
      context.setAlpha(1)
      ImageCodec.draw(image, in: CGRect(origin: .zero, size: size), context: context)
    } else if let neon = s.neon {
      neon.draw(in: context, size: size)
    } else if let pen = s.pen {
      context.setAlpha(1)
      if live { pen.drawLive(in: context) } else { pen.draw(in: context, size: size) }
    }
  }
  func isValid(_ a: Annotation, size: CGSize) throws -> Bool {
    let s = try stroke(a, size: size, live: false)
    return s.pen?.isValid ?? s.neon?.isValid ?? s.markerTool?.isValid ?? true
  }
  func makePenPreview(_ a: Annotation, size: CGSize) throws -> TelegramPenTool.RenderView? {
    guard a.tool == .pen || a.tool == .arrow else { return nil }
    var live = a
    if a.hasTerminalSample == true && a.points.count > 1 {
      live.points.removeLast()
      live.velocities?.removeLast()
      if !live.pressures.isEmpty { live.pressures.removeLast() }
    }
    let s = try stroke(live, size: size, live: true)
    return s.pen?.setupRenderView()
  }
  func updatePreview(_ a: Annotation, size: CGSize) throws {
    _ = try stroke(a, size: size, live: true)
  }
  func retain(_ ids: Set<UUID>) { cache = cache.filter { ids.contains($0.key) } }
}
