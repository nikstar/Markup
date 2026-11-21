// Source MarkerTool from Telegram DrawingTools.swift; AppKit Metal target adapter.
// Copyright Telegram Messenger. GNU GPL v2 or later.
import AppKit

final class TelegramMarkerTool {
    let uuid: UUID
    
    let drawingSize: CGSize
    let color: DrawingColor
    
    let renderLineWidth: CGFloat
    
    var translation = CGPoint()
    
    var points: [CGPoint] = []
    
    weak var metalView: TelegramMarkerRenderer?
    
    var isValid: Bool {
        return self.points.count > 6
    }
    
    var bounds: CGRect {
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = 0.0
        var maxY: CGFloat = 0.0
        
        for point in self.points {
            if point.x < minX {
                minX = point.x
            }
            if point.x > maxX {
                maxX = point.x
            }
            if point.y < minY {
                minY = point.y
            }
            if point.y > maxY {
                maxY = point.y
            }
        }
        
        return normalizeDrawingRect(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -80.0, dy: -80.0), drawingSize: self.drawingSize)
    }
        
    required init(drawingSize: CGSize, color: DrawingColor, lineWidth: CGFloat) {
        self.uuid = UUID()
        self.drawingSize = drawingSize
        self.color = color
        
        let minLineWidth = max(10.0, max(drawingSize.width, drawingSize.height) * 0.01)
        let maxLineWidth = max(20.0, max(drawingSize.width, drawingSize.height) * 0.09)
        let lineWidth = minLineWidth + (maxLineWidth - minLineWidth) * lineWidth
        
        self.renderLineWidth = lineWidth
    }
        
    private var didSetup = false
    func updatePath(_ point: DrawingPoint, state: DrawingGesturePipeline.DrawingGestureState, zoomScale: CGFloat) {
        let filterDistance: CGFloat = 10.0 / zoomScale
        if let lastPoint = self.points.last, lastPoint.distance(to: point.location) < filterDistance {
        } else {
            self.points.append(point.location)
        }
        
        self.didSetup = true
        self.metalView?.update(point, state: state, color: self.color, size: self.renderLineWidth)
    }
    
}
