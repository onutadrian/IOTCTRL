import XCTest
@testable import GoveeMacController

final class DeviceCapabilitiesTests: XCTestCase {
    func testSceneRequiresCloudTransport() {
        let caps = DeviceCapabilities(
            canPower: true,
            canBrightness: true,
            canColor: true,
            canColorTemp: true,
            canSceneCloud: true,
            lanSupported: true
        )

        XCTAssertTrue(caps.supports(.scene("movie"), via: .cloud))
        XCTAssertFalse(caps.supports(.scene("movie"), via: .lan))
    }

    func testBrightnessCapability() {
        let caps = DeviceCapabilities(
            canPower: true,
            canBrightness: false,
            canColor: false,
            canColorTemp: false,
            canSceneCloud: false,
            lanSupported: true
        )

        XCTAssertFalse(caps.supports(.brightness(40), via: .lan))
    }
}
