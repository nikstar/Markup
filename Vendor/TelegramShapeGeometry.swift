// Shape path construction from Telegram DrawingSimpleShapeEntityView.swift and
// DrawingBubbleEntityView.swift (GPL-2.0-or-later). Source proportions retained.
import AppKit

enum TelegramShapeGeometry {
    static func lineWidth(_ a:Annotation,size:CGSize) -> CGFloat {
        guard let width=a.shapeWidth else { return a.lineWidth }
        let minLineWidth=max(10,max(size.width,size.height)*0.01)
        let maxLineWidth=max(10,max(size.width,size.height)*0.05)
        return minLineWidth+(maxLineWidth-minLineWidth)*width
    }
    static func path(_ a:Annotation,size:CGSize) -> CGPath {
        guard a.rect.width>0.1,a.rect.height>0.1 else { return CGMutablePath() }
        let maxSide=max(size.width,size.height)
        let maxLineWidth=max(10,maxSide*0.05)
        var transform=CGAffineTransform(translationX:a.rect.minX,y:a.rect.minY)
        let bounds=CGRect(origin:.zero,size:a.rect.size)
        let rect=bounds.insetBy(dx:maxLineWidth*0.5,dy:maxLineWidth*0.5)
        let path:CGPath
        switch a.tool {
        case .rectangle:path=CGPath(rect:rect,transform:nil)
        case .ellipse:path=CGPath(ellipseIn:rect,transform:nil)
        case .star:path=CGPath.star(in:rect,extrusion:a.rect.width*0.2,points:5)
        case .bubble:path=CGPath.bubble(in:bounds,cornerRadius:max(10,maxSide*0.045),smallCornerRadius:max(5,maxSide*0.01),tailPosition:a.bubbleTail ?? CGPoint(x:0.16,y:a.rect.height*0.3),tailWidth:max(5,maxSide*0.1))
        default:path=CGPath(rect:bounds,transform:nil)
        }
        return path.copy(using:&transform)!
    }
    static func tailPoint(_ a:Annotation) -> CGPoint {
        let tail=a.bubbleTail ?? CGPoint(x:0.16,y:a.rect.height*0.3)
        return CGPoint(x:a.rect.minX+tail.x*a.rect.width,y:a.rect.maxY+tail.y)
    }
    static func dragTail(_ a:inout Annotation,to point:CGPoint) {
        // The normalized horizontal position follows Telegram's tail handle.
        a.bubbleTail=CGPoint(x:max(0,min(1,(point.x-a.rect.minX)/max(1,a.rect.width))),y:max(0,min(a.rect.height,point.y-a.rect.maxY)))
    }
}
