// Adapted from DrawingTextEntityView.updateText, update and sizeThatFits,
// and DrawingTextEntity.setColor. Copyright Telegram Messenger. GPL v2 or later.
import AppKit

struct TextInkRange: Codable, Equatable {
  var range: NSRange
  var color: InkColor
}

final class TelegramTextLayout {
  static let inkAttribute = NSAttributedString.Key("MarkupTextColor")
  let storage = NSTextStorage()
  let manager = TelegramTextLayoutManager()
  let container = NSTextContainer(size: CGSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
  private(set) var attributes: [NSAttributedString.Key: Any] = [:]

  init(_ a: Annotation) {
    container.widthTracksTextView = false
    container.heightTracksTextView = false
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: a.text)
    apply(a)
    setWidth(a.rect.width)
  }

  func apply(_ a: Annotation) {
    let color = a.color.ns
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = a.alignment == .left ? .left : a.alignment == .right ? .right : .center
    paragraph.lineBreakMode = .byWordWrapping
    let foreground: NSColor =
      [.filled, .stroke].contains(a.textStyle)
      ? (color.lightness > 0.99 ? .black : .white) : color
    attributes = [
      .font: NSFont(name: a.fontName, size: a.fontSize)
        ?? .systemFont(ofSize: a.fontSize, weight: .semibold),
      .foregroundColor: foreground, .paragraphStyle: paragraph,
    ]
    if a.textStyle == .regular {
      let shadow = NSShadow()
      shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
      shadow.shadowOffset = CGSize(width: 0, height: -4)
      shadow.shadowBlurRadius = 4
      attributes[.shadow] = shadow
    }
    manager.textAlignment = paragraph.alignment
    manager.frameColor =
      a.textStyle == .filled
      ? color
      : a.textStyle == .semi
        ? (color.lightness > 0.7 ? NSColor.black : .white).withAlphaComponent(0.75) : nil
    manager.strokeColor = a.textStyle == .stroke ? color : nil
    container.lineFragmentPadding = floor(a.fontSize * 0.24)
    storage.beginEditing()
    storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
    for run in a.textColors ?? []
    where run.range.location >= 0 && run.range.length > 0
      && run.range.location <= storage.length
      && run.range.length <= storage.length - run.range.location
    {
      storage.addAttributes(
        [Self.inkAttribute: run.color.ns, .foregroundColor: run.color.ns], range: run.range)
    }
    storage.endEditing()
  }

  func colors() -> [TextInkRange]? {
    var runs: [TextInkRange] = []
    storage.enumerateAttribute(Self.inkAttribute, in: NSRange(location: 0, length: storage.length))
    { color, range, _ in
      if let color = color as? NSColor {
        runs.append(TextInkRange(range: range, color: InkColor(color)))
      }
    }
    return runs.isEmpty ? nil : runs
  }

  func setWidth(_ width: CGFloat) {
    container.containerSize = CGSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
    manager.ensureLayout(for: container)
  }

  func fittedSize(maxWidth: CGFloat, minimumWidth: CGFloat) -> CGSize {
    setWidth(maxWidth)
    var width: CGFloat = 0
    manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) {
      _, used, _, _, _ in
      width = max(width, used.width)
    }
    let fitted = min(maxWidth, max(minimumWidth, ceil(width) + 20))
    setWidth(fitted)
    let font = attributes[.font] as! NSFont
    let height = max(
      manager.defaultLineHeight(for: font), manager.usedRect(for: container).maxY,
      manager.extraLineFragmentUsedRect.maxY)
    return CGSize(width: fitted, height: ceil(height))
  }
}
