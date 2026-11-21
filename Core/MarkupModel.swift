import AppKit
import UniformTypeIdentifiers

let markupType = "dev.nikstar.markup-document"

struct InkColor: Codable, Equatable {
  var red: Double
  var green: Double
  var blue: Double
  var alpha: Double = 1
  init(_ color: NSColor) {
    let c = color.usingColorSpace(.sRGB) ?? .white
    red = c.redComponent
    green = c.greenComponent
    blue = c.blueComponent
    alpha = c.alphaComponent
  }
  init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
    red = r
    green = g
    blue = b
    alpha = a
  }
  var ns: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
  static let shelfPalette: [(name: String, ink: InkColor)] = [
    ("Red", 0xff453a), ("Orange", 0xff8a00), ("Yellow", 0xffd60a), ("Green", 0x34c759),
    ("Black", 0x000000), ("Cyan", 0x63e6e2), ("Blue", 0x0a84ff), ("Purple", 0xbf5af2), ("White", 0xffffff),
  ].map { ($0.0, InkColor(rgb: $0.1)) }
  static let coral = InkColor(1, 0.31, 0.36)
  static let palette: [InkColor] = [
    .init(1, 1, 1), .init(0.12, 0.13, 0.16), .coral, .init(1, 0.63, 0.19), .init(1, 0.85, 0.25),
    .init(0.28, 0.85, 0.54), .init(0.26, 0.68, 1), .init(0.62, 0.46, 1), .init(1, 0.4, 0.75),
  ]
}

enum MarkupTool: String, Codable, CaseIterable {
  case select, pen, arrow, marker, neon, blur, eraser, line, rectangle, ellipse, star, bubble, text,
    sticker, pixelate, redact, crop, fill
  var title: String { rawValue.capitalized }
  var symbol: String {
    switch self {
    case .select: return "cursorarrow"
    case .pen: return "pencil.tip"
    case .arrow: return "arrow.up.right"
    case .marker: return "highlighter"
    case .neon: return "lightbulb.max"
    case .blur: return "drop.halffull"
    case .eraser: return "eraser"
    case .line: return "line.diagonal"
    case .rectangle: return "rectangle"
    case .ellipse: return "circle"
    case .star: return "star"
    case .bubble: return "bubble.left"
    case .text: return "textformat"
    case .sticker: return "face.smiling"
    case .pixelate: return "square.grid.3x3.fill"
    case .redact: return "rectangle.fill"
    case .crop: return "crop"
    case .fill: return "paintbrush.fill"
    }
  }
  var shortcut: String? {
    switch self {
    case .select: return "v"
    case .pen: return "p"
    case .arrow: return "a"
    case .marker: return "m"
    case .neon: return "n"
    case .blur: return "b"
    case .eraser: return "e"
    case .rectangle: return "r"
    case .ellipse: return "o"
    case .text: return "t"
    case .crop: return "c"
    case .line: return "l"
    default: return nil
    }
  }
  var isBrush: Bool { [.pen, .arrow, .marker, .neon, .blur, .eraser, .pixelate].contains(self) }
  var isInk: Bool { isBrush || self == .fill }
  var isVector: Bool { [.line, .rectangle, .ellipse, .star, .bubble, .redact].contains(self) }
}

enum TextStyle: String, Codable, CaseIterable { case regular, filled, semi, stroke, blur }
enum TextAlignment: String, Codable, CaseIterable { case left, center, right }
enum ArrowHeads: String, Codable, CaseIterable { case none, end, both }

struct Annotation: Codable, Equatable, Identifiable {
  var id = UUID()
  var tool: MarkupTool
  var points: [CGPoint] = []
  var pressures: [CGFloat] = []
  var velocities: [CGFloat]?
  // New recordings include the mouse-up sample explicitly. Nil preserves the
  // replay semantics of projects saved before terminal events were recorded.
  var hasTerminalSample: Bool?
  var brushSize: CGFloat?
  var inputZoom: CGFloat?
  var vectorMid: CGPoint?
  var vectorWidth: CGFloat?
  var bubbleTail: CGPoint?
  var shapeWidth: CGFloat?
  var rect = CGRect.zero
  var color = InkColor.coral
  var lineWidth: CGFloat = 8
  var opacity: CGFloat = 1
  var filled = false
  var blursCanvas: Bool?
  var rotation: CGFloat = 0
  var flipped = false
  var textScale: CGFloat?
  var textColors: [TextInkRange]?
  var text = ""
  var fontName = NSFont.systemFont(ofSize: 48, weight: .semibold).fontName
  var fontSize: CGFloat = 48
  var textStyle = TextStyle.regular
  var alignment = TextAlignment.center
  var arrowHeads = ArrowHeads.end
  var imageData: Data?

  var rawBounds: CGRect {
    guard let first = points.first else { return rect.standardized }
    var result = CGRect(origin: first, size: .zero)
    for p in points.dropFirst() { result = result.union(CGRect(origin: p, size: .zero)) }
    return result.insetBy(dx: -lineWidth, dy: -lineWidth)
  }
  var transform: CGAffineTransform {
    let c = rawBounds.center
    return CGAffineTransform(translationX: c.x, y: c.y).rotated(by: rotation).scaledBy(
      x: flipped ? -1 : 1, y: 1
    ).translatedBy(x: -c.x, y: -c.y)
  }
  var bounds: CGRect { rawBounds.applying(transform) }
  mutating func translate(_ delta: CGPoint) {
    points = points.map { $0 + delta }
    rect.origin = rect.origin + delta
  }
  mutating func resize(from original: CGRect, to target: CGRect) {
    let sx = target.width / max(1, original.width)
    let sy = target.height / max(1, original.height)
    func map(_ p: CGPoint) -> CGPoint {
      CGPoint(
        x: target.minX + (p.x - original.minX) * sx, y: target.minY + (p.y - original.minY) * sy)
    }
    points = points.map(map)
    rect = CGRect(
      origin: map(rect.origin), size: CGSize(width: rect.width * sx, height: rect.height * sy))
    fontSize *= min(sx, sy)
    if tool == .text { textScale = (textScale ?? 1) * min(sx, sy) }
    lineWidth *= min(sx, sy)
  }
}

struct MarkupFile: Codable, Equatable {
  var version = 1
  var source: Data
  var width: Int
  var height: Int
  var annotations: [Annotation] = []
  var crop: CGRect?
  // Absent in older projects whose erasers and stacking order used a single layer.
  var separatesInk: Bool? = true
  var paintOrder: [Annotation] {
    separatesInk == true ? annotations.filter { $0.tool.isInk } + annotations.filter { !$0.tool.isInk } : annotations
  }
  var size: CGSize { CGSize(width: width, height: height) }
  var imageBounds: CGRect { CGRect(origin: .zero, size: size) }
  var visibleRect: CGRect { (crop ?? imageBounds).intersection(imageBounds).integral }

  static func importing(_ data: Data) throws -> MarkupFile {
    let image = try ImageCodec.decode(data)
    return MarkupFile(
      source: try ImageCodec.encode(image, type: .png), width: image.width, height: image.height)
  }
  func validated() throws -> MarkupFile {
    guard version == 1, width > 0, height > 0, width <= 16384, height <= 16384,
      Double(width) * Double(height) <= 80_000_000, annotations.count <= 10000
    else { throw MarkupError.invalidDocument }
    let image = try ImageCodec.decode(source)
    guard image.width == width, image.height == height, visibleRect.width >= 1,
      visibleRect.height >= 1
    else { throw MarkupError.invalidDocument }
    func finite(_ v: CGFloat) -> Bool { v.isFinite && abs(v) < 1_000_000 }
    func good(_ r: CGRect) -> Bool { [r.minX, r.minY, r.width, r.height].allSatisfy(finite) }
    if let crop, !good(crop) { throw MarkupError.invalidDocument }
    for a in annotations {
      guard good(a.rect), a.points.count <= 200000,
        a.points.allSatisfy({ finite($0.x) && finite($0.y) }),
        finite(a.rotation), a.lineWidth.isFinite, (0.1...2048).contains(a.lineWidth),
        a.textScale.map({ $0.isFinite && $0 > 0 && $0 <= 4096 }) ?? true,
        a.fontSize.isFinite, (1...4096).contains(a.fontSize), (0...1).contains(a.opacity),
        [a.color.red, a.color.green, a.color.blue, a.color.alpha].allSatisfy({
          $0.isFinite && (0...1).contains($0)
        }),
        a.pressures.allSatisfy({ $0.isFinite && (0...2).contains($0) }),
        a.velocities?.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 10_000_000 }) ?? true,
        a.brushSize.map({ $0.isFinite && (-1...10).contains($0) }) ?? true,
        a.vectorMid.map({ finite($0.x) && finite($0.y) }) ?? true,
        a.bubbleTail.map({ finite($0.x) && finite($0.y) }) ?? true,
        a.shapeWidth.map({ finite($0) }) ?? true,
        a.vectorWidth.map({ finite($0) }) ?? true,
        a.inputZoom.map({ $0.isFinite && (0.1...16384).contains($0) }) ?? true
      else { throw MarkupError.invalidDocument }
      if let runs = a.textColors {
        let length = a.text.utf16.count
        guard runs.count <= length, runs.allSatisfy({ run in
          run.range.location >= 0 && run.range.location <= length && run.range.length > 0
            && run.range.length <= length - run.range.location
            && [run.color.red, run.color.green, run.color.blue, run.color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
        }) else { throw MarkupError.invalidDocument }
      }
      if let data = a.imageData { _ = try ImageCodec.decode(data) }
    }
    return self
  }
}

enum MarkupError: LocalizedError {
  case invalidImage, tooLarge, invalidDocument, renderingFailed
  var errorDescription: String? {
    switch self {
    case .invalidImage: return "This file does not contain a supported image."
    case .tooLarge: return "Use an image up to 16,384 pixels on each side and 80 megapixels."
    case .invalidDocument: return "This Markup document is damaged or uses an unsupported format."
    case .renderingFailed: return "The image could not be rendered."
    }
  }
}

final class EditorSession {
  var file: MarkupFile
  let undo = UndoManager()
  var onChange: (() -> Void)?
  var onCommit: ((MarkupFile, String) -> Void)?
  var selectedID: UUID? { didSet { onChange?() } }
  private let preferences: UserDefaults?
  var markupPreferences: MarkupPreferences { MarkupPreferences(preferences ?? .standard) }
  private static func brushKey(_ key: DrawingToolState.Key) -> String { "DrawingBrush.\(key.rawValue)" }
  var drawingState = DrawingState.initial {
    didSet {
      guard let preferences else { return }
      for tool in drawingState.tools where tool != oldValue.toolState(for: tool.key) {
        if let data = try? JSONEncoder().encode(tool) { preferences.set(data, forKey: Self.brushKey(tool.key)) }
      }
    }
  }
  private var loadingSourceState = false
  private struct BrushSettings {
    var color: InkColor
    var width: CGFloat
    var opacity: CGFloat
    var heads: ArrowHeads
  }
  private var settings: [MarkupTool: BrushSettings] = [:]
  var tool: MarkupTool = .pen {
    didSet {
      guard oldValue != tool else { return }
      settings[oldValue] = BrushSettings(
        color: color, width: width, opacity: opacity, heads: arrowHeads)
      loadingSourceState = true
      if let key = tool.telegramKey {
        drawingState = drawingState.withUpdatedSelectedTool(key)
        if let ink = drawingState.currentToolState.color { color = ink }
        width = TelegramBrushMetrics.width(
          tool, size: file.size, value: drawingState.currentToolState.size ?? 0.5)
        opacity = 1
        arrowHeads = .end
      } else if let saved = settings[tool] {
        color = saved.color
        width = saved.width
        opacity = saved.opacity
        arrowHeads = saved.heads
      } else {
        if tool == .text { color = InkColor(rgb: 0xffffff); opacity = 1 }
        width = 8
        arrowHeads = tool == .line ? .none : .end
      }
      loadingSourceState = false
      onChange?()
    }
  }
  var color = InkColor(rgb: 0xff453a) {
    didSet {
      if !loadingSourceState, tool.telegramKey != nil {
        drawingState = drawingState.withUpdatedColor(color)
      }
    }
  }
  var width: CGFloat = 8 {
    didSet {
      if !loadingSourceState, tool.telegramKey != nil {
        drawingState = drawingState.withUpdatedSize(
          max(0, min(1, TelegramBrushMetrics.value(tool, size: file.size, width: width))))
      }
    }
  }
  func setBrushSize(_ size: CGFloat) {
    drawingState = drawingState.withUpdatedSize(max(0, min(1, size)))
    loadingSourceState = true
    width = TelegramBrushMetrics.width(tool, size: file.size, value: max(0, min(1, size)))
    loadingSourceState = false
    onChange?()
  }
  var opacity: CGFloat = 1
  var filled = false
  var fontName = NSFont.systemFont(ofSize: 48, weight: .semibold).fontName
  var fontSize: CGFloat = 48
  var textStyle = TextStyle.filled
  var alignment = TextAlignment.center
  var arrowHeads = ArrowHeads.end
  var recognizesShapes = true
  init(file: MarkupFile, preferences: UserDefaults? = nil) {
    self.preferences = preferences
    self.file = file
    if let preferences {
      let tools = drawingState.tools.map { fallback -> DrawingToolState in
        guard let data = preferences.data(forKey: Self.brushKey(fallback.key)),
              let tool = try? JSONDecoder().decode(DrawingToolState.self, from: data),
              tool.key == fallback.key, let size = tool.size, (0...1).contains(size) else { return fallback }
        return tool
      }
      drawingState = drawingState.withUpdatedTools(tools)
      color = drawingState.currentToolState.color ?? color
    }
    let dimension = max(file.size.width, file.size.height)
    let minimum = max(10, dimension * 0.025)
    fontSize = minimum + (max(10, dimension * 0.25) - minimum) * 0.08
    width = TelegramBrushMetrics.width(.pen, size: file.size, value: drawingState.currentToolState.size ?? 0.23)
    undo.levelsOfUndo = 80
    undo.groupsByEvent = false
  }
  var selected: Annotation? { file.annotations.first { $0.id == selectedID } }
  func commit(_ next: MarkupFile, name: String, previous: MarkupFile? = nil) {
    let old = previous ?? file
    guard next != old else {
      onChange?()
      return
    }
    let ownsGroup = !undo.isUndoing && !undo.isRedoing
    if ownsGroup { undo.beginUndoGrouping() }
    undo.registerUndo(withTarget: self) { $0.commit(old, name: name) }
    undo.setActionName(name)
    file = next
    if !file.annotations.contains(where: { $0.id == selectedID }) { selectedID = nil }
    onCommit?(old, name)
    onChange?()
    if ownsGroup { undo.endUndoGrouping() }
  }
  func add(_ annotation: Annotation) {
    var next = file
    next.annotations.append(annotation)
    commit(next, name: "Add \(annotation.tool.title)")
  }
  func updateSelected(name: String, _ update: (inout Annotation) -> Void) {
    guard let i = file.annotations.firstIndex(where: { $0.id == selectedID }) else { return }
    var next = file
    update(&next.annotations[i])
    commit(next, name: name)
  }
  func deleteSelected() {
    guard selectedID != nil else { return }
    var next = file
    next.annotations.removeAll { $0.id == selectedID }
    commit(next, name: "Delete Object")
  }
  func duplicateSelected() {
    guard var a = selected else { return }
    a.id = UUID()
    let offset = round(file.visibleRect.width * 0.1)
    a.translate(CGPoint(x: a.tool == .text ? 0 : offset, y: offset))
    add(a)
    selectedID = a.id
  }
  func makeAnnotation(at p: CGPoint) -> Annotation {
    var a = Annotation(
      tool: tool, color: color, lineWidth: width, opacity: opacity, filled: filled,
      fontName: fontName, fontSize: fontSize, textStyle: textStyle, alignment: alignment,
      arrowHeads: arrowHeads)
    if let key = tool.telegramKey {
      a.brushSize = drawingState.toolState(for: key).size
      a.inputZoom = 1
      a.velocities = []
    }
    a.rect = CGRect(origin: p, size: .zero)
    return a
  }
}
