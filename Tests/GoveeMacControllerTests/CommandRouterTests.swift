import XCTest
@testable import GoveeMacController

final class CommandRouterTests: XCTestCase {
    func testUsesLANWhenSupported() async throws {
        let lan = MockTransport(kind: .lan, canHandleResult: true)
        let cloud = MockTransport(kind: .cloud, canHandleResult: true)
        let router = CommandRouter(lanTransport: lan, cloudTransport: cloud)

        let device = Fixtures.device(lanSupported: true, ip: "192.168.1.10")
        try await router.send(.power(true), to: device)

        let lanCount = await lan.sendCallCount()
        let cloudCount = await cloud.sendCallCount()
        XCTAssertEqual(lanCount, 1)
        XCTAssertEqual(cloudCount, 0)
    }

    func testFallsBackToCloudWhenLANUnavailable() async throws {
        let lan = MockTransport(kind: .lan, canHandleResult: false)
        let cloud = MockTransport(kind: .cloud, canHandleResult: true)
        let router = CommandRouter(lanTransport: lan, cloudTransport: cloud)

        let device = Fixtures.device(lanSupported: false, ip: nil)
        try await router.send(.power(true), to: device)

        let lanCount = await lan.sendCallCount()
        let cloudCount = await cloud.sendCallCount()
        XCTAssertEqual(lanCount, 0)
        XCTAssertEqual(cloudCount, 1)
    }

    func testThrowsWhenNoTransportAvailable() async {
        let lan = MockTransport(kind: .lan, canHandleResult: false)
        let cloud = MockTransport(kind: .cloud, canHandleResult: false)
        let router = CommandRouter(lanTransport: lan, cloudTransport: cloud)

        let device = Fixtures.device(lanSupported: false, ip: nil)

        do {
            try await router.send(.scene("x"), to: device)
            XCTFail("Expected transportUnavailable error")
        } catch let error as AppError {
            if case .transportUnavailable = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor MockTransport: CommandTransport {
    let kind: TransportKind
    let canHandleResult: Bool
    private var sendCount: Int = 0

    init(kind: TransportKind, canHandleResult: Bool) {
        self.kind = kind
        self.canHandleResult = canHandleResult
    }

    nonisolated func canHandle(command: ControlCommand, for device: Device) -> Bool {
        canHandleResult
    }

    func send(_ command: ControlCommand, to device: Device) async throws {
        sendCount += 1
    }

    func sendCallCount() -> Int {
        sendCount
    }
}
