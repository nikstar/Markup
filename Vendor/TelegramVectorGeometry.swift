// Rendering and handle mathematics ported from DrawingVectorEntityView.swift.
// Copyright Telegram Messenger. GNU GPL v2 or later.
import AppKit

enum TelegramVectorGeometry {
    static func midPointPositionFor(start:CGPoint,end:CGPoint,length:CGFloat,height:CGFloat) -> CGPoint {
        let distance=end.distance(to:start)
        let angle=start.angle(to:end)
        let p1=start.pointAt(distance:distance*length,angle:angle)
        let p2=p1.pointAt(distance:distance*height,angle:angle + .pi*0.5)
        return p2
    }
    static func midPoint(_ entity:TelegramVectorEntity) -> CGPoint { midPointPositionFor(start:entity.start,end:entity.end,length:entity.mid.0,height:entity.mid.1) }
    static func path(_ entity:TelegramVectorEntity) -> CGPath {
        let minLineWidth=max(10.0,max(entity.referenceDrawingSize.width,entity.referenceDrawingSize.height)*0.01)
        let maxLineWidth=max(10.0,max(entity.referenceDrawingSize.width,entity.referenceDrawingSize.height)*0.05)
        let lineWidth=minLineWidth+(maxLineWidth-minLineWidth)*entity.lineWidth
        return CGPath.curve(start:entity.start,end:entity.end,mid:midPoint(entity),lineWidth:lineWidth,
                            arrowSize:entity.type == .line ? nil : CGSize(width:lineWidth*1.5,height:lineWidth*3),twoSided:entity.type == .twoSidedArrow)
    }
    static func drag(_ entity:TelegramVectorEntity,handle:Int,delta:CGPoint) {
        var updatedStart=entity.start
        var updatedMid=entity.mid
        var updatedEnd=entity.end
        if handle == 0 { updatedStart.x += delta.x;updatedStart.y += delta.y }
        else if handle == 2 { updatedEnd.x += delta.x;updatedEnd.y += delta.y }
        else if handle == 1 {
            var updatedMidPoint=midPoint(entity);updatedMidPoint.x += delta.x;updatedMidPoint.y += delta.y
            let distance=updatedStart.distance(to:updatedEnd)
            // A coincident pair of desktop handles must not produce an invalid document.
            guard distance>0.0001 else { return }
            let pointOnLine=updatedMidPoint.perpendicularPointOnLine(start:updatedStart,end:updatedEnd)
            let angle=updatedStart.angle(to:updatedEnd)
            let midAngle=updatedStart.angle(to:updatedMidPoint)
            var height=updatedMidPoint.distance(to:pointOnLine)/distance
            var deltaAngle=midAngle-angle
            if deltaAngle > .pi { deltaAngle=angle-2 * .pi }
            else if deltaAngle < -.pi { deltaAngle=angle+2 * .pi }
            if deltaAngle<0 { height *= -1 }
            let length=updatedStart.distance(to:pointOnLine)/distance
            updatedMid=(length,height)
        } else { updatedStart.x += delta.x;updatedStart.y += delta.y;updatedEnd.x += delta.x;updatedEnd.y += delta.y }
        entity.start=updatedStart;entity.mid=updatedMid;entity.end=updatedEnd
    }
}
extension Annotation {
    func telegramVector(size:CGSize) -> TelegramVectorEntity {
        let minWidth=max(10,max(size.width,size.height)*0.01),maxWidth=max(10,max(size.width,size.height)*0.05)
        let normalized=vectorWidth ?? ((lineWidth-minWidth)/max(1,maxWidth-minWidth))
        let entity=TelegramVectorEntity(type:arrowHeads == .none ? .line : arrowHeads == .both ? .twoSidedArrow : .oneSidedArrow,color:color,lineWidth:normalized)
        entity.drawingSize=size;entity.referenceDrawingSize=size
        entity.start=points.first ?? .zero;entity.end=points.last ?? .zero
        if let vectorMid { entity.mid=(vectorMid.x,vectorMid.y) }
        else if points.count==3 {
            entity.mid=(0.5,0)
            TelegramVectorGeometry.drag(entity,handle:1,delta:points[1]-TelegramVectorGeometry.midPoint(entity))
        }
        return entity
    }
    mutating func apply(_ entity:TelegramVectorEntity) {
        points=[entity.start,TelegramVectorGeometry.midPoint(entity),entity.end]
        vectorMid=CGPoint(x:entity.mid.0,y:entity.mid.1)
    }
}
