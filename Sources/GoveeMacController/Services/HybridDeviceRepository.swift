import Foundation

final class HybridDeviceRepository: DeviceRepository, @unchecked Sendable {
    private let cloudClient: CloudClient
    private let lanDiscovery: LanDiscoveryServiceProtocol

    init(cloudClient: CloudClient, lanDiscovery: LanDiscoveryServiceProtocol) {
        self.cloudClient = cloudClient
        self.lanDiscovery = lanDiscovery
    }

    func fetchDevices() async throws -> [Device] {
        let cloudClient = self.cloudClient
        let lanDiscovery = self.lanDiscovery

        let cloudDevices = try await cloudClient.listDevices()
        let lanDevices = await lanDiscovery.discover(timeout: 2.5)

        let lanByMAC = Dictionary(uniqueKeysWithValues: lanDevices.map { device in
            (device.mac.lowercased().replacingOccurrences(of: ":", with: ""), device)
        })

        var output: [Device] = []
        var seenLanKeys: Set<String> = []

        for cloudDevice in cloudDevices {
            let normalized = cloudDevice.mac.lowercased().replacingOccurrences(of: ":", with: "")
            let lanMatch = lanByMAC[normalized]

            let caps = capabilities(from: cloudDevice.supportCommands, lanAvailable: lanMatch != nil)
            let profile: TransportProfile = caps.lanSupported ? .hybrid : .cloud

            output.append(
                Device(
                    id: cloudDevice.id,
                    model: cloudDevice.model,
                    name: cloudDevice.name,
                    mac: cloudDevice.mac,
                    ip: lanMatch?.ip,
                    isOnline: lanMatch?.isOnline ?? cloudDevice.isOnline,
                    isOn: lanMatch?.isOn,
                    brightness: lanMatch?.brightness,
                    color: nil,
                    colorTemp: nil,
                    capabilities: caps,
                    transportProfile: profile
                )
            )

            if lanMatch != nil {
                seenLanKeys.insert(normalized)
            }
        }

        for lanDevice in lanDevices {
            let normalized = lanDevice.mac.lowercased().replacingOccurrences(of: ":", with: "")
            guard !seenLanKeys.contains(normalized) else {
                continue
            }

            output.append(
                Device(
                    id: lanDevice.mac,
                    model: lanDevice.model ?? "Unknown",
                    name: "LAN Device (\(lanDevice.mac))",
                    mac: lanDevice.mac,
                    ip: lanDevice.ip,
                    isOnline: lanDevice.isOnline ?? true,
                    isOn: lanDevice.isOn,
                    brightness: lanDevice.brightness,
                    color: nil,
                    colorTemp: nil,
                    capabilities: DeviceCapabilities(
                        canPower: true,
                        canBrightness: true,
                        canColor: false,
                        canColorTemp: false,
                        canSceneCloud: false,
                        lanSupported: true
                    ),
                    transportProfile: .lan
                )
            )
        }

        return output.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func capabilities(from supportCommands: Set<String>, lanAvailable: Bool) -> DeviceCapabilities {
        let normalized = Set(supportCommands.map { $0.lowercased() })
        return DeviceCapabilities(
            canPower: normalized.contains("turn") || normalized.contains("powerstate"),
            canBrightness: normalized.contains("brightness"),
            canColor: false,
            canColorTemp: false,
            canSceneCloud: false,
            lanSupported: lanAvailable
        )
    }
}
