// Direct AppKit port of Telegram-iOS DrawingUI/Sources/DrawingUtils.swift.
// Copyright Telegram Messenger. GNU GPL v2 or later.
// UIKit presentation classes removed; stroke geometry and constants retained.
import AppKit

import simd

class Matrix {
    private(set) var m: [Float]
    
    private init() {
        m = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        ]
    }
    
    @discardableResult
    func translation(x: Float, y: Float, z: Float) -> Matrix {
        m[12] = x
        m[13] = y
        m[14] = z
        return self
    }
    
    @discardableResult
    func scaling(x: Float, y: Float, z: Float) -> Matrix {
        m[0] = x
        m[5] = y
        m[10] = z
        return self
    }
    
    static var identity:Matrix { Matrix() }
}

struct Vertex {
    var position: vector_float4
    var texCoord: vector_float2
    
    init(position: CGPoint, texCoord: CGPoint) {
        self.position = position.toFloat4()
        self.texCoord = texCoord.toFloat2()
    }
}

struct Point {
    var position: vector_float4
    var color: vector_float4
    var angle: Float
    var size: Float

    init(x: CGFloat, y: CGFloat, color: DrawingColor, size: CGFloat, angle: CGFloat = 0) {
        self.position = vector_float4(Float(x), Float(y), 0, 1)
        self.size = Float(size)
        self.color = color.toFloat4()
        self.angle = Float(angle)
    }
}

extension CGPoint {
    func toFloat4(z: CGFloat = 0, w: CGFloat = 1) -> vector_float4 {
        return [Float(x), Float(y), Float(z) ,Float(w)]
    }
    
    func toFloat2() -> vector_float2 {
        return [Float(x), Float(y)]
    }
    
    func offsetBy(_ offset: CGPoint) -> CGPoint {
        return self.offsetBy(dx: offset.x, dy: offset.y)
    }
}

