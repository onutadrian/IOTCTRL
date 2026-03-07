import Foundation

final class CommandRouter: DeviceController, @unchecked Sendable {
    private let lanTransport: CommandTransport
    private let cloudTransport: CommandTransport

    init(lanTransport: CommandTransport, cloudTransport: CommandTransport) {
        self.lanTransport = lanTransport
        self.cloudTransport = cloudTransport
    }

    func preferredTransport(for device: Device, command: ControlCommand) -> TransportKind? {
        if lanTransport.canHandle(command: command, for: device) {
            return .lan
        }

        if cloudTransport.canHandle(command: command, for: device) {
            return .cloud
        }

        return nil
    }

    func send(_ command: ControlCommand, to device: Device) async throws {
        switch preferredTransport(for: device, command: command) {
        case .lan:
            try await lanTransport.send(command, to: device)
        case .cloud:
            try await cloudTransport.send(command, to: device)
        case .none:
            throw AppError.transportUnavailable(device: device.name)
        }
    }
}
