// Adapted from Telegram-iOS, submodules/DrawingUI/Sources/DrawingUtils.swift.
// Copyright Telegram Messenger. Licensed under GNU GPL v2 or later.
// UIKit-free point mathematics, shape paths, and cubic spline solver.
import AppKit

extension CGPoint {
    func isEqual(to point: CGPoint, epsilon: CGFloat) -> Bool {
        if x - epsilon <= point.x && point.x <= x + epsilon && y - epsilon <= point.y && point.y <= y + epsilon {
            return true
        }
        return false
    }
    
    static public func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    
    static public func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    
    static public func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        return CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
    
    static public func / (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        return CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }
    
    var length: CGFloat {
        return sqrt(self.x * self.x + self.y * self.y)
    }
    
    static func middle(p1: CGPoint, p2: CGPoint) -> CGPoint {
        return CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
    }
    
    func distance(to point: CGPoint) -> CGFloat {
        return sqrt(pow((point.x - self.x), 2) + pow((point.y - self.y), 2))
    }
    
    func distanceSquared(to point: CGPoint) -> CGFloat {
        return pow((point.x - self.x), 2) + pow((point.y - self.y), 2)
    }
    
    func angle(to point: CGPoint) -> CGFloat {
        return atan2((point.y - self.y), (point.x - self.x))
    }
    
    func pointAt(distance: CGFloat, angle: CGFloat) -> CGPoint {
        return CGPoint(x: distance * cos(angle) + self.x, y: distance * sin(angle) + self.y)
    }
    
    func point(to point: CGPoint, t: CGFloat) -> CGPoint {
        return CGPoint(x: self.x + t * (point.x - self.x), y: self.y + t * (point.y - self.y))
    }
    
    func perpendicularPointOnLine(start: CGPoint, end: CGPoint) -> CGPoint {
        let l2 = start.distanceSquared(to: end)
        if l2.isZero {
            return start
        }
        let t = ((self.x - start.x) * (end.x - start.x) + (self.y - start.y) * (end.y - start.y)) / l2
        return CGPoint(x: start.x + t * (end.x - start.x), y: start.y + t * (end.y - start.y))
    }
    
    func linearBezierPoint(to: CGPoint, t: CGFloat) -> CGPoint {
      let dx = to.x - x;
      let dy = to.y - y;
      
      let px = x + (t * dx);
      let py = y + (t * dy);
      
      return CGPoint(x: px, y: py)
    }
    
    fileprivate func _cubicBezier(_ t: CGFloat, _ start: CGFloat, _ c1: CGFloat, _ c2: CGFloat, _ end: CGFloat) -> CGFloat {
        let _t = 1 - t;
        let _t2 = _t * _t;
        let _t3 = _t * _t * _t ;
        let t2 = t * t;
        let t3 = t * t * t;
        
        return  _t3 * start +
        3.0 * _t2 * t * c1 +
        3.0 * _t * t2 * c2 +
        t3 * end;
    }
    
    func cubicBezierPoint(to: CGPoint, controlPoint1 c1: CGPoint, controlPoint2 c2: CGPoint, t: CGFloat) -> CGPoint {
        let x = _cubicBezier(t, self.x, c1.x, c2.x, to.x);
        let y = _cubicBezier(t, self.y, c1.y, c2.y, to.y);
        
        return CGPoint(x: x, y: y);
    }
    
    fileprivate func _quadBezier(_ t: CGFloat, _ start: CGFloat, _ c1: CGFloat, _ end: CGFloat) -> CGFloat {
        let _t = 1 - t;
        let _t2 = _t * _t;
        let t2 = t * t;
        
        return  _t2 * start +
        2 * _t * t * c1 +
        t2 * end;
    }
    
    func quadBezierPoint(to: CGPoint, controlPoint: CGPoint, t: CGFloat) -> CGPoint {
        let x = _quadBezier(t, self.x, controlPoint.x, to.x);
        let y = _quadBezier(t, self.y, controlPoint.y, to.y);
        
        return CGPoint(x: x, y: y);
    }
}


extension CGPath {
    static func star(in rect: CGRect, extrusion: CGFloat, points: Int = 5) -> CGPath {
        func pointFrom(angle: CGFloat, radius: CGFloat, offset: CGPoint) -> CGPoint {
            return CGPoint(x: radius * cos(angle) + offset.x, y: radius * sin(angle) + offset.y)
        }
        
        let path = CGMutablePath()

        let center = rect.center.offsetBy(dx: 0.0, dy: rect.height * 0.05)
        var angle: CGFloat = -CGFloat(.pi / 2.0)
        let angleIncrement = CGFloat(.pi * 2.0 / Double(points))
        let radius = rect.width / 2.0

        var firstPoint = true
        for _ in 1 ... points {
            let point = center.pointAt(distance: radius, angle: angle)
            let nextPoint = center.pointAt(distance: radius, angle: angle + angleIncrement)
            let midPoint = center.pointAt(distance: extrusion, angle: angle + angleIncrement * 0.5)

            if firstPoint {
                firstPoint = false
                path.move(to: point)
            }
            path.addLine(to: midPoint)
            path.addLine(to: nextPoint)

            angle += angleIncrement
        }
        path.closeSubpath()
        
        return path
    }
    
    static func arrow(from point: CGPoint, controlPoint: CGPoint, width: CGFloat, height: CGFloat, isOpen: Bool) -> CGPath {
        let angle = atan2(point.y - controlPoint.y, point.x - controlPoint.x)
        let angleAdjustment = atan2(width, -height)
        let distance = hypot(width, height)
        
        let path = CGMutablePath()
        path.move(to: point)
        path.addLine(to: point.pointAt(distance: distance, angle: angle - angleAdjustment))
        if isOpen {
            path.addLine(to: point)
        }
        path.addLine(to: point.pointAt(distance: distance, angle: angle + angleAdjustment))
        if isOpen {
            path.addLine(to: point)
        } else {
            path.closeSubpath()
        }
        return path
    }
    
    static func curve(start: CGPoint, end: CGPoint, mid: CGPoint, lineWidth: CGFloat?, arrowSize: CGSize?, twoSided: Bool = false) -> CGPath {
        let linePath = CGMutablePath()
                
        let controlPoints = configureControlPoints(data: [start, mid, end])
        var lineStart = start
        if let arrowSize = arrowSize, twoSided {
            lineStart = start.pointAt(distance: -arrowSize.height * 0.5, angle: controlPoints[0].ctrl1.angle(to: start))
        }
        linePath.move(to: lineStart)
        linePath.addCurve(to: mid, control1: controlPoints[0].ctrl1, control2: controlPoints[0].ctrl2)
        
        var lineEnd = end
        if let arrowSize = arrowSize {
            lineEnd = end.pointAt(distance: -arrowSize.height * 0.5, angle: controlPoints[1].ctrl1.angle(to: end))
        }
        linePath.addCurve(to: lineEnd, control1: controlPoints[1].ctrl1, control2: controlPoints[1].ctrl2)
        
        let path: CGMutablePath
        if let lineWidth = lineWidth, let mutablePath = linePath.copy(strokingWithWidth: lineWidth, lineCap: .square, lineJoin: .round, miterLimit: 0.0).mutableCopy() {
            path = mutablePath
        } else {
            path = linePath
        }
        
        if let arrowSize = arrowSize {
            let arrowPath = arrow(from: end, controlPoint: controlPoints[1].ctrl1, width: arrowSize.width, height: arrowSize.height, isOpen: false)
            path.addPath(arrowPath)
            
            if twoSided {
                let secondArrowPath = arrow(from: start, controlPoint: controlPoints[0].ctrl1, width: arrowSize.width, height: arrowSize.height, isOpen: false)
                path.addPath(secondArrowPath)
            }
        }
    
        return path
    }
    
    static func bubble(in rect: CGRect, cornerRadius: CGFloat, smallCornerRadius: CGFloat, tailPosition: CGPoint, tailWidth: CGFloat) -> CGPath {
        let r1 = min(cornerRadius, min(rect.width, rect.height) / 3.0)
        let r2 = min(smallCornerRadius, min(rect.width, rect.height) / 10.0)
        
        let ax = tailPosition.x * rect.width
        let ay = tailPosition.y
        
        let width = min(max(tailWidth, ay / 2.0), rect.width / 4.0)
        let angle = atan2(ay, width)
        let h = r2 / tan(angle / 2.0)
        
        let r1a = min(r1, min(rect.maxX - ax, ax - rect.minX) * 0.5)
        let r2a = min(r2, min(rect.maxX - ax, ax - rect.minX) * 0.2)
        
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: rect.minX + r1, y: rect.minY + r1), radius: r1, startAngle: .pi, endAngle: .pi * 3.0 / 2.0, clockwise: false)
        path.addArc(center: CGPoint(x: rect.maxX - r1, y: rect.minY + r1), radius: r1, startAngle: -.pi / 2.0, endAngle: 0.0, clockwise: false)
                        
        if ax > rect.width / 2.0 {
            if ax < rect.width - 1 {
                path.addArc(center: CGPoint(x: rect.maxX - r1a, y: rect.maxY - r1a), radius: r1a, startAngle: 0.0, endAngle: .pi / 2.0, clockwise: false)
                path.addArc(center: CGPoint(x: rect.minX + ax + r2a, y: rect.maxY + r2a), radius: r2a, startAngle: .pi * 3.0 / 2.0, endAngle: .pi, clockwise: true)
            }
            path.addLine(to: CGPoint(x: rect.minX + ax, y: rect.maxY + ay))
            path.addArc(center: CGPoint(x: rect.minX + ax - width - r2, y: rect.maxY + h), radius: h, startAngle: -(CGFloat.pi / 2 - angle), endAngle: CGFloat.pi * 3 / 2, clockwise: true)
            path.addArc(center: CGPoint(x: rect.minX + r1, y: rect.maxY - r1), radius: r1, startAngle: CGFloat.pi / 2, endAngle: CGFloat.pi, clockwise: false)
        } else {
            path.addArc(center: CGPoint(x: rect.maxX - r1, y: rect.maxY - r1), radius: r1, startAngle: 0, endAngle: CGFloat.pi / 2, clockwise: false)
            path.addArc(center: CGPoint(x: rect.minX + ax + width + r2, y: rect.maxY + h), radius: h, startAngle: CGFloat.pi * 3 / 2, endAngle: CGFloat.pi * 3 / 2 - angle, clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX + ax, y: rect.maxY + ay))
            if ax > 1 {
                path.addArc(center: CGPoint(x: rect.minX + ax - r2a, y: rect.maxY + r2a), radius: r2a, startAngle: 0, endAngle: CGFloat.pi * 3 / 2, clockwise: true)
                path.addArc(center: CGPoint(x: rect.minX + r1a, y: rect.maxY - r1a), radius: r1a, startAngle: CGFloat.pi / 2, endAngle: CGFloat.pi, clockwise: false)
            }
        }
        
        path.closeSubpath()
        
        return path
    }
}

private func configureControlPoints(data: [CGPoint]) -> [(ctrl1: CGPoint, ctrl2: CGPoint)] {
    let segments = data.count - 1
    
    if segments == 1 {
        let p0 = data[0]
        let p3 = data[1]
        
        return [(p0, p3)]
    } else if segments > 1 {
        var ad: [CGFloat] = []
        var d: [CGFloat] = []
        var bd: [CGFloat] = []
        
        var rhsArray: [CGPoint] = []
        
        for i in 0 ..< segments {
            var rhsXValue: CGFloat = 0.0
            var rhsYValue: CGFloat = 0.0
            
            let p0 = data[i]
            let p3 = data[i + 1]
            
            if i == 0 {
                bd.append(0.0)
                d.append(2.0)
                ad.append(1.0)
                
                rhsXValue = p0.x + 2.0 * p3.x
                rhsYValue = p0.y + 2.0 * p3.y
            } else if i == segments - 1 {
                bd.append(2.0)
                d.append(7.0)
                ad.append(0.0)
                
                rhsXValue = 8.0 * p0.x + p3.x
                rhsYValue = 8.0 * p0.y + p3.y
            } else {
                bd.append(1.0)
                d.append(4.0)
                ad.append(1.0)
                
                rhsXValue = 4.0 * p0.x + 2.0 * p3.x
                rhsYValue = 4.0 * p0.y + 2.0 * p3.y
            }
            
            rhsArray.append(CGPoint(x: rhsXValue, y: rhsYValue))
        }
        
        var firstControlPoints: [CGPoint?] = []
        var secondControlPoints: [CGPoint?] = []
        
        var controlPoints : [(CGPoint, CGPoint)] = []
        
        var solutionSet1 = [CGPoint?]()
        solutionSet1 = Array(repeating: nil, count: segments)
        
        ad[0] = ad[0] / d[0]
        rhsArray[0].x = rhsArray[0].x / d[0]
        rhsArray[0].y = rhsArray[0].y / d[0]
        
        if segments > 2 {
            for i in 1...segments - 2 {
                let rhsValueX = rhsArray[i].x
                let prevRhsValueX = rhsArray[i - 1].x
                
                let rhsValueY = rhsArray[i].y
                let prevRhsValueY = rhsArray[i - 1].y
                
                ad[i] = ad[i] / (d[i] - bd[i] * ad[i - 1]);
                
                let exp1x = (rhsValueX - (bd[i] * prevRhsValueX))
                let exp1y = (rhsValueY - (bd[i] * prevRhsValueY))
                let exp2 = (d[i] - bd[i] * ad[i - 1])
                
                rhsArray[i].x = exp1x / exp2
                rhsArray[i].y = exp1y / exp2
            }
        }
        
        let lastElementIndex = segments - 1
        let exp1 = (rhsArray[lastElementIndex].x - bd[lastElementIndex] * rhsArray[lastElementIndex - 1].x)
        let exp1y = (rhsArray[lastElementIndex].y - bd[lastElementIndex] * rhsArray[lastElementIndex - 1].y)
        let exp2 = (d[lastElementIndex] - bd[lastElementIndex] * ad[lastElementIndex - 1])
        rhsArray[lastElementIndex].x = exp1 / exp2
        rhsArray[lastElementIndex].y = exp1y / exp2
        
        solutionSet1[lastElementIndex] = rhsArray[lastElementIndex]
        
        for i in (0..<lastElementIndex).reversed() {
            let controlPointX = rhsArray[i].x - (ad[i] * solutionSet1[i + 1]!.x)
            let controlPointY = rhsArray[i].y - (ad[i] * solutionSet1[i + 1]!.y)
            
            solutionSet1[i] = CGPoint(x: controlPointX, y: controlPointY)
        }
        
        firstControlPoints = solutionSet1
        
        for i in (0..<segments) {
            if i == (segments - 1) {
                
                let lastDataPoint = data[i + 1]
                let p1 = firstControlPoints[i]
                guard let controlPoint1 = p1 else { continue }
                
                let controlPoint2X = 0.5 * (lastDataPoint.x + controlPoint1.x)
                let controlPoint2y = 0.5 * (lastDataPoint.y + controlPoint1.y)
                
                let controlPoint2 = CGPoint(x: controlPoint2X, y: controlPoint2y)
                secondControlPoints.append(controlPoint2)
            }else {
                
                let dataPoint = data[i+1]
                let p1 = firstControlPoints[i+1]
                guard let controlPoint1 = p1 else { continue }
                
                let controlPoint2X = 2*dataPoint.x - controlPoint1.x
                let controlPoint2Y = 2*dataPoint.y - controlPoint1.y
                
                secondControlPoints.append(CGPoint(x: controlPoint2X, y: controlPoint2Y))
            }
        }
        
        for i in (0..<segments) {
            guard let firstControlPoint = firstControlPoints[i] else { continue }
            guard let secondControlPoint = secondControlPoints[i] else { continue }
            
            controlPoints.append((firstControlPoint, secondControlPoint))
        }

        return controlPoints
    }
    return []
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}
