import Foundation

enum TransportKind: String, Sendable {
    case lan = "LAN"
    case cloud = "Cloud"
}

protocol DeviceRepository: Sendable {
    func fetchDevices() async throws -> [Device]
}

protocol DeviceController: Sendable {
    func send(_ command: ControlCommand, to device: Device) async throws
    func preferredTransport(for device: Device, command: ControlCommand) -> TransportKind?
}

protocol CommandTransport: Sendable {
    var kind: TransportKind { get }
    func canHandle(command: ControlCommand, for device: Device) -> Bool
    func send(_ command: ControlCommand, to device: Device) async throws
}
