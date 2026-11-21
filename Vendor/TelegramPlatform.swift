// Platform adapters for the directly ported Telegram drawing algorithms (GPL-2.0-or-later).
// No UIKit is linked. Keeping the source API names makes changes against upstream inspectable.
import AppKit
import simd

typealias DrawingColor = InkColor
typealias UIColor = NSColor
typealias UIImage = NSImage
typealias UIBezierPath = TelegramBezierPath
typealias UIFont = NSFont
typealias UIEdgeInsets = NSEdgeInsets
func UIGraphicsGetCurrentContext() -> CGContext? { NSGraphicsContext.current?.cgContext }
func floorToScreenPixels(_ value:CGFloat) -> CGFloat { floor(value*2)/2 }

struct DrawingPoint { let location:CGPoint; let velocity:CGFloat; var x:CGFloat { location.x }; var y:CGFloat { location.y } }
enum DrawingGesturePipeline { enum DrawingGestureState { case began,changed,ended,cancelled } }
extension InkColor {
    init(rgb:UInt32) { self.init(Double((rgb>>16)&255)/255,Double((rgb>>8)&255)/255,Double(rgb&255)/255) }
    static var clear:InkColor { InkColor(0,0,0,0) }
    func withUpdatedAlpha(_ alpha:CGFloat) -> InkColor { var c=self; c.alpha=Double(alpha); return c }
    func toUIColor() -> NSColor { ns }
    func toCGColor() -> CGColor { ns.cgColor }
    func toFloat4() -> SIMD4<Float> { SIMD4(Float(red),Float(green),Float(blue),Float(alpha)) }
}
extension NSColor {
    convenience init(rgb:UInt32) { self.init(srgbRed:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:1) }
    var lightness:CGFloat { let c=usingColorSpace(.sRGB) ?? .black; return (max(c.redComponent,c.greenComponent,c.blueComponent)+min(c.redComponent,c.greenComponent,c.blueComponent))/2 }
    func mixedWith(_ other:NSColor,alpha:CGFloat) -> NSColor { blended(withFraction:alpha,of:other) ?? self }
    func withMultipliedBrightnessBy(_ value:CGFloat) -> NSColor { let c=usingColorSpace(.sRGB) ?? .black; return NSColor(srgbRed:c.redComponent*value,green:c.greenComponent*value,blue:c.blueComponent*value,alpha:c.alphaComponent) }
}
extension NSImage {
    func pngData() -> Data? { guard let image=cgImage else { return nil };return try? ImageCodec.encode(image,type:.png) }
    var cgImage:CGImage? { cgImage(forProposedRect:nil,context:nil,hints:nil) }
}
final class TelegramBezierPath {
    private var path=CGMutablePath()
    init() {}
    init(roundedRect:CGRect,cornerRadius:CGFloat) { path.addRoundedRect(in:roundedRect,cornerWidth:cornerRadius,cornerHeight:cornerRadius) }
    init(arcCenter:CGPoint,radius:CGFloat,startAngle:CGFloat,endAngle:CGFloat,clockwise:Bool) { addArc(withCenter:arcCenter,radius:radius,startAngle:startAngle,endAngle:endAngle,clockwise:clockwise) }
    func addArc(withCenter center:CGPoint,radius:CGFloat,startAngle:CGFloat,endAngle:CGFloat,clockwise:Bool) { path.addArc(center:center,radius:radius,startAngle:startAngle,endAngle:endAngle,clockwise:!clockwise) }
    func fill() { guard let c=UIGraphicsGetCurrentContext() else { return };c.addPath(path);c.fillPath() }
    func stroke() {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        c.saveGState()
        c.setLineWidth(1) // UIBezierPath owns its stroke width independently of the enclosing brush.
        c.addPath(path)
        c.strokePath()
        c.restoreGState()
    }
    var cgPath:CGPath { path }
    var bounds:CGRect { path.boundingBoxOfPath }
    func move(to p:CGPoint) { path.move(to:p) }
    func addLine(to p:CGPoint) { path.addLine(to:p) }
    func addQuadCurve(to p:CGPoint,controlPoint:CGPoint) { path.addQuadCurve(to:p,control:controlPoint) }
    func addCurve(to p:CGPoint,controlPoint1:CGPoint,controlPoint2:CGPoint) { path.addCurve(to:p,control1:controlPoint1,control2:controlPoint2) }
    func append(_ other:TelegramBezierPath) { path.addPath(other.cgPath) }
}
final class DrawingContext {
    let context:CGContext
    init?(size:CGSize,scale:CGFloat,clear:Bool) {
        guard let c=try? ImageCodec.context(width:max(1,Int(size.width*scale)),height:max(1,Int(size.height*scale))) else { return nil }
        c.scaleBy(x:scale,y:scale); context=c
    }
    func withFlippedContext(_ block:(CGContext)->Void) { block(context) }
    func generateImage() -> NSImage? { context.makeImage().map { NSImage(cgImage:$0,size:.zero) } }
}
func normalizeDrawingRect(_ rect:CGRect,drawingSize:CGSize) -> CGRect { rect.intersection(CGRect(origin:.zero,size:drawingSize)) }
