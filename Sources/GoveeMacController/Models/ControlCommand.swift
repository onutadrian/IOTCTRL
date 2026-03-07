import Foundation

struct RGBColor: Codable, Hashable, Sendable {
    var r: Int
    var g: Int
    var b: Int

    init(r: Int, g: Int, b: Int) {
        self.r = Self.clamp(r)
        self.g = Self.clamp(g)
        self.b = Self.clamp(b)
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 0), 255)
    }
}

enum ControlCommand: Hashable, Sendable {
    case power(Bool)
    case brightness(Int)
    case color(RGBColor)
    case colorTemp(Int)
    case scene(String)

    var coalescingKey: String {
        switch self {
        case .brightness:
            return "brightness"
        case .color:
            return "color"
        case .colorTemp:
            return "colorTemp"
        case .power(let value):
            return "power-\(value)"
        case .scene(let id):
            return "scene-\(id)"
        }
    }

    var fingerprint: String {
        switch self {
        case .power(let value):
            return "power-\(value)"
        case .brightness(let value):
            return "brightness-\(value)"
        case .color(let rgb):
            return "color-\(rgb.r)-\(rgb.g)-\(rgb.b)"
        case .colorTemp(let value):
            return "colorTemp-\(value)"
        case .scene(let id):
            return "scene-\(id)"
        }
    }
}
