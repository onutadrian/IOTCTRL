@testable import GoveeMacController

enum Fixtures {
    static func device(lanSupported: Bool = true, ip: String? = "192.168.1.40") -> Device {
        Device(
            id: "AA:BB:CC:DD",
            model: "H6001",
            name: "Fixture Light",
            mac: "AA:BB:CC:DD",
            ip: ip,
            isOnline: true,
            isOn: true,
            brightness: 42,
            color: RGBColor(r: 12, g: 34, b: 56),
            colorTemp: 3200,
            capabilities: DeviceCapabilities(
                canPower: true,
                canBrightness: true,
                canColor: true,
                canColorTemp: true,
                canSceneCloud: true,
                lanSupported: lanSupported
            ),
            transportProfile: lanSupported ? .hybrid : .cloud
        )
    }
}
