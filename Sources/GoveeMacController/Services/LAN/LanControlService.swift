import Foundation
import Network

protocol LanControlServiceProtocol: Sendable {
    func send(_ command: ControlCommand, to device: Device) async throws
}

actor LanControlService: LanControlServiceProtocol {
    func send(_ command: ControlCommand, to device: Device) async throws {
        guard let ip = device.ip, !ip.isEmpty else {
            throw AppError.missingLANAddress(device: device.name)
        }

        guard let content = try payload(for: command) else {
            throw AppError.unsupportedCommand(command: command, device: device.name)
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: 4003)!,
            using: .udp
        )

        connection.start(queue: DispatchQueue(label: "govee.lan.control"))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: content, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: AppError.networkFailure(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            })
        }

        connection.cancel()
    }

    private func payload(for command: ControlCommand) throws -> Data? {
        let message: [String: Any]

        switch command {
        case .power(let isOn):
            message = [
                "msg": [
                    "cmd": "turn",
                    "data": ["value": isOn ? 1 : 0]
                ]
            ]
        case .brightness(let value):
            message = [
                "msg": [
                    "cmd": "brightness",
                    "data": ["value": min(max(value, 0), 100)]
                ]
            ]
        case .color(let rgb):
            message = [
                "msg": [
                    "cmd": "colorwc",
                    "data": [
                        "color": ["r": rgb.r, "g": rgb.g, "b": rgb.b],
                        "colorTemInKelvin": 0
                    ]
                ]
            ]
        case .colorTemp(let kelvin):
            message = [
                "msg": [
                    "cmd": "colorwc",
                    "data": [
                        "color": ["r": 0, "g": 0, "b": 0],
                        "colorTemInKelvin": min(max(kelvin, 2000), 9000)
                    ]
                ]
            ]
        case .scene:
            return nil
        }

        return try JSONSerialization.data(withJSONObject: message, options: [])
    }
}

final class LanTransport: CommandTransport, @unchecked Sendable {
    let kind: TransportKind = .lan

    private let service: LanControlServiceProtocol

    init(service: LanControlServiceProtocol) {
        self.service = service
    }

    func canHandle(command: ControlCommand, for device: Device) -> Bool {
        guard device.capabilities.lanSupported, device.ip != nil else {
            return false
        }

        return device.capabilities.supports(command, via: .lan)
    }

    func send(_ command: ControlCommand, to device: Device) async throws {
        guard canHandle(command: command, for: device) else {
            throw AppError.unsupportedCommand(command: command, device: device.name)
        }

        try await service.send(command, to: device)
    }
}
