import Foundation

enum TransportProfile: String, Sendable {
    case lan = "LAN"
    case cloud = "Cloud"
    case hybrid = "Hybrid"
}

struct DeviceCapabilities: Hashable, Sendable {
    var canPower: Bool
    var canBrightness: Bool
    var canColor: Bool
    var canColorTemp: Bool
    var canSceneCloud: Bool
    var lanSupported: Bool

    static let none = DeviceCapabilities(
        canPower: false,
        canBrightness: false,
        canColor: false,
        canColorTemp: false,
        canSceneCloud: false,
        lanSupported: false
    )

    func supports(_ command: ControlCommand, via transport: TransportKind) -> Bool {
        switch command {
        case .power:
            return canPower
        case .brightness:
            return canBrightness
        case .color:
            return canColor
        case .colorTemp:
            return canColorTemp
        case .scene:
            return transport == .cloud && canSceneCloud
        }
    }
}

struct Device: Identifiable, Hashable, Sendable {
    let id: String
    let model: String
    var name: String
    var mac: String
    var ip: String?
    var isOnline: Bool?
    var isOn: Bool?
    var brightness: Int?
    var color: RGBColor?
    var colorTemp: Int?
    var capabilities: DeviceCapabilities
    var transportProfile: TransportProfile
    var isManualLANOverride: Bool = false

    var normalizedMAC: String {
        mac.lowercased().replacingOccurrences(of: ":", with: "")
    }
}
