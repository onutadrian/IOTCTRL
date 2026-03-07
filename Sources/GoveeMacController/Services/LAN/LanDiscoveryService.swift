import Darwin
import Foundation

struct LanDiscoveredDevice: Hashable, Sendable {
    let mac: String
    let ip: String
    let model: String?
    let isOnline: Bool?
    let isOn: Bool?
    let brightness: Int?
}

protocol LanDiscoveryServiceProtocol: Sendable {
    func discover(timeout: TimeInterval) async -> [LanDiscoveredDevice]
}

final class LanDiscoveryService: LanDiscoveryServiceProtocol, @unchecked Sendable {
    func discover(timeout: TimeInterval = 5) async -> [LanDiscoveredDevice] {
        await Task.detached(priority: .userInitiated) {
            Self.discoverSynchronously(timeout: timeout)
        }.value
    }

    private static func discoverSynchronously(timeout: TimeInterval) -> [LanDiscoveredDevice] {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else {
            return []
        }
        defer { close(sock) }

        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        var bindAddress = sockaddr_in()
        bindAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddress.sin_family = sa_family_t(AF_INET)
        bindAddress.sin_port = in_port_t(4002).bigEndian
        bindAddress.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &bindAddress) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            return []
        }

        _ = fcntl(sock, F_SETFL, O_NONBLOCK)

        var accumulator = DiscoveryAccumulator()
        let payload = Data(#"{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}"#.utf8)

        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(max(timeout, 1.5))
        var nextProbe = startedAt

        while Date() < deadline {
            let now = Date()
            if now >= nextProbe {
                sendScan(payload: payload, to: "239.255.255.250", port: 4001, socket: sock)
                sendScan(payload: payload, to: "255.255.255.255", port: 4001, socket: sock)
                nextProbe = now.addingTimeInterval(0.6)
            }

            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                var source = sockaddr_in()
                var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)

                let receivedBytes = withUnsafeMutablePointer(to: &source) { pointer -> ssize_t in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(sock, &buffer, buffer.count, 0, $0, &sourceLength)
                    }
                }

                if receivedBytes > 0 {
                    let packet = Data(buffer.prefix(Int(receivedBytes)))
                    accumulator.ingest(packet)
                    continue
                }

                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }

                break
            }

            usleep(100_000)
        }

        return accumulator.devices
    }

    private static func sendScan(payload: Data, to host: String, port: UInt16, socket: Int32) {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian

        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return
        }

        payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                return
            }

            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(socket, base, payload.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

private struct DiscoveryAccumulator {
    private(set) var devicesByMAC: [String: LanDiscoveredDevice] = [:]

    mutating func ingest(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = json["msg"] as? [String: Any],
              let payload = msg["data"] as? [String: Any] else {
            return
        }

        let mac = (payload["device"] as? String) ?? (payload["bleMac"] as? String) ?? ""
        let ip = (payload["ip"] as? String) ?? ""
        let model = payload["sku"] as? String

        guard !mac.isEmpty, !ip.isEmpty else {
            return
        }

        let statePayload = payload["state"] as? [String: Any] ?? [:]
        let mergedState = statePayload.merging(payload, uniquingKeysWith: { stateValue, _ in stateValue })

        let isOnline = boolValue(in: mergedState, keys: ["online", "isOnline"])
        let isOn = boolValue(in: mergedState, keys: ["onOff", "onoff", "powerSwitch", "powerState", "turn", "switch", "power"])
        let brightness = intValue(in: mergedState, keys: ["brightness", "bright", "dimming"])

        let normalized = mac.lowercased().replacingOccurrences(of: ":", with: "")
        if var existing = devicesByMAC[normalized] {
            existing = LanDiscoveredDevice(
                mac: mac,
                ip: ip,
                model: model ?? existing.model,
                isOnline: isOnline ?? existing.isOnline,
                isOn: isOn ?? existing.isOn,
                brightness: brightness ?? existing.brightness
            )
            devicesByMAC[normalized] = existing
            return
        }

        devicesByMAC[normalized] = LanDiscoveredDevice(
            mac: mac,
            ip: ip,
            model: model,
            isOnline: isOnline,
            isOn: isOn,
            brightness: brightness
        )
    }

    var devices: [LanDiscoveredDevice] {
        Array(devicesByMAC.values)
    }

    private func boolValue(in dict: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            guard let value = dict[key] else {
                continue
            }

            if let boolValue = value as? Bool {
                return boolValue
            }

            if let numberValue = value as? NSNumber {
                return numberValue.intValue != 0
            }

            if let stringValue = value as? String {
                let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["on", "true", "1", "yes"].contains(normalized) {
                    return true
                }
                if ["off", "false", "0", "no"].contains(normalized) {
                    return false
                }
            }
        }

        return nil
    }

    private func intValue(in dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = dict[key] else {
                continue
            }

            if let intValue = value as? Int {
                return intValue
            }

            if let doubleValue = value as? Double {
                return Int(doubleValue.rounded())
            }

            if let numberValue = value as? NSNumber {
                return numberValue.intValue
            }

            if let stringValue = value as? String {
                let trimmed = stringValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "%", with: "")
                if let intValue = Int(trimmed) {
                    return intValue
                }
                if let doubleValue = Double(trimmed) {
                    return Int(doubleValue.rounded())
                }
            }
        }

        return nil
    }
}
