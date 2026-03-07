import XCTest
@testable import GoveeMacController

final class CloudCommandDispatcherTests: XCTestCase {
    func testCoalescesRapidBrightnessUpdates() async throws {
        let sent = Locked<[ControlCommand]>([])
        let dispatcher = CloudCommandDispatcher(minInterval: 0) { _, command in
            await sent.mutate { values in
                values.append(command)
            }
        }

        let device = Fixtures.device()

        async let a: Void = dispatcher.submit(device: device, command: .brightness(10))
        async let b: Void = dispatcher.submit(device: device, command: .brightness(20))
        async let c: Void = dispatcher.submit(device: device, command: .brightness(80))

        _ = try await (a, b, c)

        let commands = await sent.value
        XCTAssertEqual(commands.count, 1)
        if case .brightness(let value)? = commands.first {
            XCTAssertTrue([10, 20, 80].contains(value))
        } else {
            XCTFail("Expected one coalesced brightness command")
        }
    }
}

private actor Locked<T> {
    private var storage: T

    init(_ storage: T) {
        self.storage = storage
    }

    var value: T {
        storage
    }

    func mutate(_ transform: (inout T) -> Void) {
        transform(&storage)
    }
}
