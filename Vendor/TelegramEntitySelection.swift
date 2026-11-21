// AppKit port of the handle layouts in Telegram's DrawingSimpleShapeEntityView,
// DrawingBubbleEntityView, DrawingTextEntityView, DrawingStickerEntityView and
// DrawingVectorEntityView. Copyright Telegram Messenger, GPL-2.0-or-later.
import AppKit

enum SelectionHandle: Equatable {
  case edge(CGFloat, CGFloat)
  case radial, rotation
  case vector(Int)
  case tail
}

struct TelegramEntitySelection {
  let annotation: Annotation
  let size: CGSize
  let scale: CGFloat
  private(set) var handles: [(kind: SelectionHandle, point: CGPoint)] = []
  private var border: CGPath?
  private var dash: CGFloat = 0

  init(_ a: Annotation, size: CGSize, scale: CGFloat) {
    annotation = a
    self.size = size
    self.scale = scale
    var rect = a.rawBounds
    switch a.tool {
    case .line where a.points.count >= 2:
      let entity = a.telegramVector(size: size)
      handles = [entity.start, TelegramVectorGeometry.midPoint(entity), entity.end].enumerated().map
      {
        (.vector($0.offset), $0.element)
      }
      return
    case .rectangle, .ellipse, .star:
      let inset = min(
        max(10, max(size.width, size.height) * 0.05) / 2, min(rect.width, rect.height) / 2)
      rect = rect.insetBy(dx: inset, dy: inset)
    case .text, .sticker:
      let circular = a.tool == .sticker && a.imageData == nil
      if circular {
        let side = max(rect.width, rect.height)
        rect = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
      }
      rect = rect.insetBy(dx: -10 / scale, dy: -10 / scale)
      let radius = min(11 / scale, min(rect.width, rect.height) / 2)
      if circular {
        border = CGPath(ellipseIn: rect, transform: nil)
        dash = .pi * rect.width / 10 * 0.25
      } else {
        border = CGPath(
          roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let perimeter = 2 * (rect.width + rect.height - radius * (4 - .pi))
        dash = perimeter / (a.tool == .sticker ? 24 : 12) * 0.25
      }
      handles = [
        (.radial, CGPoint(x: rect.minX, y: rect.midY)),
        (.radial, CGPoint(x: rect.maxX, y: rect.midY)),
      ]
      return
    default: break
    }
    for y: CGFloat in [-1, 0, 1] {
      for x: CGFloat in [-1, 0, 1] where x != 0 || y != 0 {
        handles.append(
          (
            .edge(x, y),
            CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
          ))
      }
    }
    if a.tool == .bubble { handles.append((.tail, TelegramShapeGeometry.tailPoint(a))) }
    if a.tool.isBrush {
      handles.append((.rotation, CGPoint(x: rect.midX, y: rect.minY - 24 / scale)))
    }
  }

  func hit(_ point: CGPoint) -> SelectionHandle? {
    let local = point.applying(annotation.transform.inverted())
    // Choose the nearest center when small objects have overlapping touch areas.
    guard
      let nearest = handles.min(by: { $0.point.distance(to: local) < $1.point.distance(to: local) }
      ),
      nearest.point.distance(to: local) <= 14 / scale
    else { return nil }
    return nearest.kind
  }

  // Caller installs the image-to-view transform. Handle sizes are screen points.
  func draw(in c: CGContext, backingScale: CGFloat) {
    c.saveGState()
    defer { c.restoreGState() }
    c.concatenate(annotation.transform)
    if let border {
      c.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
      c.setLineWidth(2 / scale)
      c.setLineCap(.round)
      c.setLineDash(phase: 0, lengths: [dash, dash])
      c.addPath(border)
      c.strokePath()
      c.setLineDash(phase: 0, lengths: [])
    }
    c.setStrokeColor(NSColor.white.cgColor)
    c.setLineWidth((1 + 1 / backingScale) / scale)
    for handle in handles {
      let r = 4.5 / scale
      let rect = CGRect(x: handle.point.x - r, y: handle.point.y - r, width: r * 2, height: r * 2)
      let control = handle.kind == .tail || handle.kind == .vector(1)
      c.setFillColor(NSColor(rgb: control ? 0x00ff00 : 0x0a60ff).cgColor)
      c.fillEllipse(in: rect)
      c.strokeEllipse(in: rect)
    }
  }

  func drag(_ handle: SelectionHandle, from start: CGPoint, to end: CGPoint, constrained: Bool)
    -> Annotation
  {
    var a = annotation
    let inverse = a.transform.inverted()
    let local = end.applying(inverse)
    let delta = local - start.applying(inverse)
    let b = a.rawBounds
    switch handle {
    case .vector(let index):
      let entity = a.telegramVector(size: size)
      TelegramVectorGeometry.drag(entity, handle: index, delta: delta)
      a.apply(entity)
    case .tail: TelegramShapeGeometry.dragTail(&a, to: local)
    case .radial, .rotation:
      let center = b.center
      if handle == .radial {
        let ratio = end.distance(to: center) / max(0.001, start.distance(to: center))
        let factor = max(1 / max(a.fontSize, 1), min(4096 / max(a.fontSize, 1), ratio))
        a.resize(
          from: b, to: b.insetBy(dx: b.width * (1 - factor) / 2, dy: b.height * (1 - factor) / 2))
      }
      a.rotation += center.angle(to: end) - center.angle(to: start)
      if constrained { a.rotation = (a.rotation / (.pi / 12)).rounded() * (.pi / 12) }
    case .edge(let x, let y):
      let minimum =
        [.rectangle, .ellipse, .star, .bubble].contains(a.tool)
        ? min(size.width, size.height) * 0.2 : 12
      var width = x == 0 ? b.width : max(min(minimum, b.width), b.width + x * delta.x)
      var height = y == 0 ? b.height : max(min(minimum, b.height), b.height + y * delta.y)
      if constrained || a.tool == .star {
        let ratio = max(0.001, b.width / max(0.001, b.height))
        if x == 0 || (y != 0 && abs(delta.y * ratio) > abs(delta.x)) {
          width = height * ratio
        } else {
          height = width / ratio
        }
      }
      let center = CGPoint(
        x: b.midX + x * (width - b.width) / 2, y: b.midY + y * (height - b.height) / 2
      ).applying(a.transform)
      let target = CGRect(
        x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
      if a.points.isEmpty { a.rect = target } else { a.resize(from: b, to: target) }
    }
    return a
  }
}
