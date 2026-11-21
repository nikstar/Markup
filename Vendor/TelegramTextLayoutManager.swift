// AppKit port of DrawingTextLayoutManager from Telegram DrawingTextEntityView.swift.
// Copyright Telegram Messenger. GNU GPL v2 or later.
import AppKit

final class TelegramTextLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var radius: CGFloat
    var maxIndex: Int = 0
    
    private(set) var path: UIBezierPath?
    var rectArray: [CGRect] = []
    
    var strokeColor: UIColor?
    var strokeWidth: CGFloat = 0.0
    var strokeOffset: CGPoint = .zero
    
    var frameColor: UIColor?
    var frameInsets = UIEdgeInsets()
    
    var textAlignment: NSTextAlignment = .natural
    
    override init() {
        self.radius = 8.0
        
        super.init()
        delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect rect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect used: UnsafeMutablePointer<NSRect>, baselineOffset baseline: UnsafeMutablePointer<CGFloat>,
                       in container: NSTextContainer, forGlyphRange glyphs: NSRange) -> Bool {
        guard glyphs.length > 0, let storage = textStorage else { return false }
        let index = characterIndexForGlyph(at: glyphs.location)
        guard index < storage.length, let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont,
              used.pointee.height <= defaultLineHeight(for: font) + 1 else { return false }
        // UIKit lays out fractional font metrics. The iOS San Francisco font
        // uses 1950/-494 design units, measured at 16, 48 and 96 pt (2048 UPM).
        let system = font.fontName == telegramTextFonts[0].name
        let ascent = system ? font.pointSize * 1950 / 2048 : font.ascender
        let descent = system ? font.pointSize * 494 / 2048 : -font.descender
        let height = ascent + descent + max(0, font.leading)
        rect.pointee.size.height = height
        used.pointee.size.height = height
        baseline.pointee = ascent
        return true
    }

    private func prepare() {
        self.path = nil
        self.rectArray.removeAll()
                
        self.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: self.numberOfGlyphs)) { rect, usedRect, textContainer, glyphRange, _ in
            var ignoreRange = false
            let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let substring = ((self.textStorage?.string ?? "") as NSString).substring(with: characterRange)
            if substring.trimmingCharacters(in: .newlines).isEmpty {
                ignoreRange = true
            }
            
            var usedRect = usedRect
            if substring.hasSuffix(" ") && self.textAlignment != .right {
                usedRect.size.width -= floorToScreenPixels(usedRect.height * 0.145)
            }
            
            if !ignoreRange {
                let newRect = CGRect(origin: CGPoint(x: usedRect.minX - floorToScreenPixels(self.frameInsets.left * usedRect.height), y: usedRect.minY - floorToScreenPixels(self.frameInsets.top * usedRect.height)), size: CGSize(width: usedRect.width + floorToScreenPixels((self.frameInsets.left + self.frameInsets.right) * usedRect.height), height: usedRect.height + floorToScreenPixels((self.frameInsets.top + self.frameInsets.bottom) * usedRect.height)))
                self.rectArray.append(newRect)
            }
        }
        
        self.preprocess()
    }
    
    private func preprocess() {
        self.maxIndex = 0
        if self.rectArray.count < 2 {
            return
        }
        for i in 1 ..< self.rectArray.count {
            self.maxIndex = i
            self.processRectIndex(i)
        }
    }
    
    private func processRectIndex(_ index: Int) {
        guard self.rectArray.count >= 2 && index > 0 && index <= self.maxIndex else {
            return
        }
        
        var last = self.rectArray[index - 1]
        var cur = self.rectArray[index]
        
        self.radius = cur.height * 0.2
        
        let doubleRadius = self.radius * 2.5
        
        var t1 = ((cur.minX - last.minX < doubleRadius) && (cur.minX > last.minX)) || ((cur.maxX - last.maxX > -doubleRadius) && (cur.maxX < last.maxX))
        let t2 = ((last.minX - cur.minX < doubleRadius) && (last.minX > cur.minX)) || ((last.maxX - cur.maxX > -doubleRadius) && (last.maxX < cur.maxX))
        
        if t2 {
            let newRect = CGRect(origin: CGPoint(x: cur.minX, y: last.minY), size: CGSize(width: cur.width, height: last.height))
            self.rectArray[index - 1] = newRect
            self.processRectIndex(index - 1)
        }
        
        last = self.rectArray[index - 1]
        cur = self.rectArray[index]
        
        t1 = ((cur.minX - last.minX < doubleRadius) && (cur.minX > last.minX)) || ((cur.maxX - last.maxX > -doubleRadius) && (cur.maxX < last.maxX))
        
        if t1 {
            let newRect = CGRect(origin: CGPoint(x: last.minX, y: cur.minY), size: CGSize(width: last.width, height: cur.height))
            self.rectArray[index] = newRect
            self.processRectIndex(index + 1)
        }
    }
    
    override func showCGGlyphs(_ glyphs: UnsafePointer<CGGlyph>, positions: UnsafePointer<CGPoint>, count glyphCount: Int, font: UIFont, textMatrix: CGAffineTransform, attributes: [NSAttributedString.Key : Any] = [:], in graphicsContext: CGContext) {
        graphicsContext.saveGState()
        defer { graphicsContext.restoreGState() }
        // UIKit uses grayscale glyph coverage even on opaque caption backgrounds.
        graphicsContext.setAllowsFontSmoothing(false)
        graphicsContext.setShouldSmoothFonts(false)
        if let strokeColor = self.strokeColor {
            graphicsContext.setStrokeColor(strokeColor.cgColor)
            graphicsContext.setLineJoin(.round)
            
            let lineWidth = self.strokeWidth > 0.0 ? self.strokeWidth : font.pointSize / 9.0
            graphicsContext.setLineWidth(lineWidth)
            graphicsContext.setTextDrawingMode(.stroke)
            
            graphicsContext.saveGState()
            graphicsContext.translateBy(x: self.strokeOffset.x, y: self.strokeOffset.y)
            
            super.showCGGlyphs(glyphs, positions: positions, count: glyphCount, font: font, textMatrix: textMatrix, attributes: attributes, in: graphicsContext)
            
            graphicsContext.restoreGState()
            
            let textColor: UIColor = attributes[NSAttributedString.Key.foregroundColor] as? UIColor ?? UIColor.white
            
            graphicsContext.setFillColor(textColor.cgColor)
            graphicsContext.setTextDrawingMode(.fill)
        }
        super.showCGGlyphs(glyphs, positions: positions, count: glyphCount, font: font, textMatrix: textMatrix, attributes: attributes, in: graphicsContext)
    }
    
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        if let frameColor = self.frameColor, let context = UIGraphicsGetCurrentContext() {
            context.saveGState()
            
            context.translateBy(x: origin.x, y: origin.y)
                        
            context.setBlendMode(.copy)
            context.setFillColor(frameColor.cgColor)
            context.setStrokeColor(frameColor.cgColor)
            
            self.prepare()
            self.preprocess()
            
            let path = UIBezierPath()
            
            var last: CGRect = .null
            for i in 0 ..< self.rectArray.count {
                let cur = self.rectArray[i]
                self.radius = cur.height * 0.2
                
                path.append(UIBezierPath(roundedRect: cur, cornerRadius: self.radius))
                if i == 0 {
                    last = cur
                } else if i > 0 && abs(last.maxY -  cur.minY) < 15.0 {
                    let a = cur.origin
                    let b = CGPoint(x: cur.maxX, y: cur.minY)
                    let c = CGPoint(x: last.minX, y: last.maxY)
                    let d = CGPoint(x: last.maxX, y: last.maxY)
                    
                    if a.x - c.x >= 2.0 * self.radius {
                        let addPath = UIBezierPath(arcCenter: CGPoint(x: a.x - self.radius, y: a.y + self.radius), radius: self.radius, startAngle: .pi * 0.5 * 3.0, endAngle: 0.0, clockwise: true)
                        addPath.append(
                            UIBezierPath(arcCenter: CGPoint(x: a.x + self.radius, y: a.y + self.radius), radius: self.radius, startAngle: .pi, endAngle: 3.0 * .pi * 0.5, clockwise: true)
                        )
                        addPath.addLine(to: CGPoint(x: a.x - self.radius, y: a.y))
                        path.append(addPath)
                    }
                    if a.x == c.x {
                        path.move(to: CGPoint(x: a.x, y: a.y - self.radius))
                        path.addLine(to: CGPoint(x: a.x, y: a.y + self.radius))
                        path.addArc(withCenter: CGPoint(x: a.x + self.radius, y: a.y + self.radius), radius: self.radius, startAngle: .pi, endAngle: .pi * 0.5 * 3.0, clockwise: true)
                        path.addArc(withCenter: CGPoint(x: a.x + self.radius, y: a.y - self.radius), radius: self.radius, startAngle: .pi * 0.5, endAngle: .pi, clockwise: true)
                    }
                    if d.x - b.x >= 2.0 * self.radius {
                        let addPath = UIBezierPath(arcCenter: CGPoint(x: b.x + self.radius, y: b.y + self.radius), radius: self.radius, startAngle: .pi * 0.5 * 3.0, endAngle: .pi, clockwise: false)
                        addPath.append(
                            UIBezierPath(arcCenter: CGPoint(x: b.x - self.radius, y: b.y + self.radius), radius: self.radius, startAngle: 0.0, endAngle: 3.0 * .pi * 0.5, clockwise: false)
                        )
                        addPath.addLine(to: CGPoint(x: b.x + self.radius, y: b.y))
                        path.append(addPath)
                    }
                    if d.x == b.x {
                        path.move(to: CGPoint(x: b.x, y: b.y - self.radius))
                        path.addLine(to: CGPoint(x: b.x, y: b.y + self.radius))
                        path.addArc(withCenter: CGPoint(x: b.x - self.radius, y: b.y + self.radius), radius: self.radius, startAngle: 0.0, endAngle: 3.0 * .pi * 0.5, clockwise: false)
                        path.addArc(withCenter: CGPoint(x: b.x - self.radius, y: b.y - self.radius), radius: self.radius, startAngle: .pi * 0.5, endAngle: 0.0, clockwise: false)
                    }
                    if c.x - a.x >= 2.0 * self.radius {
                        let addPath = UIBezierPath(arcCenter: CGPoint(x: c.x - self.radius, y: c.y - self.radius), radius: self.radius, startAngle: .pi * 0.5, endAngle: 0.0, clockwise: false)
                        addPath.append(
                            UIBezierPath(arcCenter: CGPoint(x: c.x + self.radius, y: c.y - self.radius), radius: self.radius, startAngle: .pi, endAngle: .pi * 0.5, clockwise: false)
                        )
                        addPath.addLine(to: CGPoint(x: c.x - self.radius, y: c.y))
                        path.append(addPath)
                    }
                    if b.x  - d.x >= 2.0 * self.radius {
                        let addPath = UIBezierPath(arcCenter: CGPoint(x: d.x + self.radius, y: d.y - self.radius), radius: self.radius, startAngle: .pi * 0.5, endAngle: .pi, clockwise: true)
                        addPath.append(
                            UIBezierPath(arcCenter: CGPoint(x: d.x - self.radius, y: d.y - self.radius), radius: self.radius, startAngle: 0.0, endAngle: .pi * 0.5, clockwise: true)
                        )
                        addPath.addLine(to: CGPoint(x: d.x + self.radius, y: d.y))
                        path.append(addPath)
                    }
                    last = cur
                } else {
                    last = cur
                }
            }
            self.path = path
            
            self.path?.fill()
            self.path?.stroke()
            
            context.restoreGState()
        }
        // NSTextView paints its selected range and marked text through TextKit here.
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

