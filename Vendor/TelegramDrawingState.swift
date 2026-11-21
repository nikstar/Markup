// Directly copied from Telegram DrawingScreen.swift, GPL-2.0-or-later.
import AppKit

enum DrawingToolState: Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case brushState
        case eraserState
    }
    
    enum Key: Int32, RawRepresentable, CaseIterable, Codable {
        case pen = 0
        case arrow = 1
        case marker = 2
        case neon = 3
        case blur = 4
        case eraser = 5
    }
    
    struct BrushState: Equatable, Codable {
        private enum CodingKeys: String, CodingKey {
            case color
            case size
        }
        
        let color: DrawingColor
        let size: CGFloat
        
        init(color: DrawingColor, size: CGFloat) {
            self.color = color
            self.size = size
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.color = try container.decode(DrawingColor.self, forKey: .color)
            self.size = try container.decode(CGFloat.self, forKey: .size)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.color, forKey: .color)
            try container.encode(self.size, forKey: .size)
        }
        
        func withUpdatedColor(_ color: DrawingColor) -> BrushState {
            return BrushState(color: color, size: self.size)
        }
        
        func withUpdatedSize(_ size: CGFloat) -> BrushState {
            return BrushState(color: self.color, size: size)
        }
    }
    
    struct EraserState: Equatable, Codable {
        private enum CodingKeys: String, CodingKey {
            case size
        }
        
        let size: CGFloat
        
        init(size: CGFloat) {
            self.size = size
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.size = try container.decode(CGFloat.self, forKey: .size)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.size, forKey: .size)
        }
        
        func withUpdatedSize(_ size: CGFloat) -> EraserState {
            return EraserState(size: size)
        }
    }
    
    case pen(BrushState)
    case arrow(BrushState)
    case marker(BrushState)
    case neon(BrushState)
    case blur(EraserState)
    case eraser(EraserState)
    
    func withUpdatedColor(_ color: DrawingColor) -> DrawingToolState {
        switch self {
        case let .pen(state):
            return .pen(state.withUpdatedColor(color))
        case let .arrow(state):
            return .arrow(state.withUpdatedColor(color))
        case let .marker(state):
            return .marker(state.withUpdatedColor(color))
        case let .neon(state):
            return .neon(state.withUpdatedColor(color))
        case .blur, .eraser:
            return self
        }
    }
    
    func withUpdatedSize(_ size: CGFloat) -> DrawingToolState {
        switch self {
        case let .pen(state):
            return .pen(state.withUpdatedSize(size))
        case let .arrow(state):
            return .arrow(state.withUpdatedSize(size))
        case let .marker(state):
            return .marker(state.withUpdatedSize(size))
        case let .neon(state):
            return .neon(state.withUpdatedSize(size))
        case let .blur(state):
            return .blur(state.withUpdatedSize(size))
        case let .eraser(state):
            return .eraser(state.withUpdatedSize(size))
        }
    }
    
    var color: DrawingColor? {
        switch self {
        case let .pen(state), let .arrow(state), let .marker(state), let .neon(state):
            return state.color
        default:
            return nil
        }
    }
    
    var size: CGFloat? {
        switch self {
        case let .pen(state), let .arrow(state), let .marker(state), let .neon(state):
            return state.size
        case let .blur(state), let .eraser(state):
            return state.size
        }
    }
    
    var key: DrawingToolState.Key {
        switch self {
        case .pen:
            return .pen
        case .arrow:
            return .arrow
        case .marker:
            return .marker
        case .neon:
            return .neon
        case .blur:
            return .blur
        case .eraser:
            return .eraser
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeValue = try container.decode(Int32.self, forKey: .type)
        if let type = DrawingToolState.Key(rawValue: typeValue) {
            switch type {
            case .pen:
                self = .pen(try container.decode(BrushState.self, forKey: .brushState))
            case .arrow:
                self = .arrow(try container.decode(BrushState.self, forKey: .brushState))
            case .marker:
                self = .marker(try container.decode(BrushState.self, forKey: .brushState))
            case .neon:
                self = .neon(try container.decode(BrushState.self, forKey: .brushState))
            case .blur:
                self = .blur(try container.decode(EraserState.self, forKey: .eraserState))
            case .eraser:
                self = .eraser(try container.decode(EraserState.self, forKey: .eraserState))
            }
        } else {
            self = .pen(BrushState(color: DrawingColor(rgb: 0x000000), size: 0.5))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pen(state):
            try container.encode(DrawingToolState.Key.pen.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .arrow(state):
            try container.encode(DrawingToolState.Key.arrow.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .marker(state):
            try container.encode(DrawingToolState.Key.marker.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .neon(state):
            try container.encode(DrawingToolState.Key.neon.rawValue, forKey: .type)
            try container.encode(state, forKey: .brushState)
        case let .blur(state):
            try container.encode(DrawingToolState.Key.blur.rawValue, forKey: .type)
            try container.encode(state, forKey: .eraserState)
        case let .eraser(state):
            try container.encode(DrawingToolState.Key.eraser.rawValue, forKey: .type)
            try container.encode(state, forKey: .eraserState)
        }
    }
}

struct DrawingState: Equatable {
    let selectedTool: DrawingToolState.Key
    let tools: [DrawingToolState]
    
    var currentToolState: DrawingToolState {
        return self.toolState(for: self.selectedTool)
    }
    
    func toolState(for key: DrawingToolState.Key) -> DrawingToolState {
        for tool in self.tools {
            if tool.key == key {
                return tool
            }
        }
        return .eraser(DrawingToolState.EraserState(size: 0.5))
    }
    
    func withUpdatedSelectedTool(_ selectedTool: DrawingToolState.Key) -> DrawingState {
        return DrawingState(
            selectedTool: selectedTool,
            tools: self.tools
        )
    }
    
    func withUpdatedTools(_ tools: [DrawingToolState]) -> DrawingState {
        return DrawingState(
            selectedTool: self.selectedTool,
            tools: tools
        )
    }
    
    func withUpdatedColor(_ color: DrawingColor) -> DrawingState {
        var tools = self.tools
        if let index = tools.firstIndex(where: { $0.key == self.selectedTool }) {
            let updated = tools[index].withUpdatedColor(color)
            tools.remove(at: index)
            tools.insert(updated, at: index)
        }
        
        return DrawingState(
            selectedTool: self.selectedTool,
            tools: tools
        )
    }
    
    func withUpdatedSize(_ size: CGFloat) -> DrawingState {
        var tools = self.tools
        if let index = tools.firstIndex(where: { $0.key == self.selectedTool }) {
            let updated = tools[index].withUpdatedSize(size)
            tools.remove(at: index)
            tools.insert(updated, at: index)
        }
        
        return DrawingState(
            selectedTool: self.selectedTool,
            tools: tools
        )
    }
            
    static var initial: DrawingState {
        return DrawingState(
            selectedTool: .pen,
            tools: [
                .pen(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xff453a), size: 0.23)),
                .arrow(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xff8a00), size: 0.23)),
                .marker(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.75)),
                .neon(DrawingToolState.BrushState(color: DrawingColor(rgb: 0x34c759), size: 0.4)),
                .blur(DrawingToolState.EraserState(size: 0.5)),
                .eraser(DrawingToolState.EraserState(size: 0.5))
            ]
        )
    }
    
    func forVideo() -> DrawingState {
        return DrawingState(
            selectedTool: self.selectedTool,
            tools: self.tools.filter { tool in
                if case .blur = tool {
                    return false
                } else {
                    return true
                }
            }
        )
    }
}
