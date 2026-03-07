import Foundation
import XCTest
@testable import GoveeMacController

final class CloudClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.requestHandler = nil
    }

    func testListDevicesDecodesSupportCommands() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Govee-API-Key"), "test-key")

            let json = #"{"data":{"devices":[{"device":"AA:BB:CC","model":"H6159","deviceName":"Desk Strip","supportCmds":["turn",{"name":"brightness"}]}]}}"#
            let data = Data(json.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = makeClient()
        let devices = try await client.listDevices()

        XCTAssertEqual(devices.count, 1)
        XCTAssertTrue(devices[0].supportCommands.contains("turn"))
        XCTAssertTrue(devices[0].supportCommands.contains("brightness"))
    }

    func testGetStateDecodesPowerBrightnessAndOnlineVariants() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("/v1/devices/state") == true)

            let json = #"{"data":{"properties":[{"name":"powerSwitch","value":1},{"name":"brightness","value":{"value":"37"}},{"name":"online","value":true}]}}"#
            let data = Data(json.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = makeClient()
        let state = try await client.getState(deviceID: "AA:BB:CC", model: "H6159")

        XCTAssertEqual(state.isOn, true)
        XCTAssertEqual(state.brightness, 37)
        XCTAssertEqual(state.isOnline, true)
    }

    func testGetStateDecodesLegacyPropertiesArrayShape() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("/v1/devices/state") == true)

            let json = #"{"data":{"properties":[{"online":true},{"powerState":"on"},{"brightness":"59"}]}}"#
            let data = Data(json.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = makeClient()
        let state = try await client.getState(deviceID: "AA:BB:CC", model: "H6159")

        XCTAssertEqual(state.isOnline, true)
        XCTAssertEqual(state.isOn, true)
        XCTAssertEqual(state.brightness, 59)
    }

    func testGetStateDecodesColorAndColorTemperatureVariants() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("/v1/devices/state") == true)

            let json = #"{"data":{"properties":[{"name":"colorTemInKelvin","value":"3200"},{"name":"color","value":{"value":{"r":"12","g":34,"b":56}}}]}}"#
            let data = Data(json.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = makeClient()
        let state = try await client.getState(deviceID: "AA:BB:CC", model: "H6159")

        XCTAssertEqual(state.colorTemp, 3200)
        XCTAssertEqual(state.color, RGBColor(r: 12, g: 34, b: 56))
    }

    func testRateLimitReturnsRetryAfter() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "3"]
            )!
            return (response, Data())
        }

        let client = makeClient()

        do {
            try await client.control(deviceID: "AA:BB", model: "H6001", command: .power(true))
            XCTFail("Expected rate limit error")
        } catch let error as AppError {
            if case .rateLimited(let retryAfter) = error {
                XCTAssertEqual(retryAfter, 3)
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeClient() -> CloudClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        return CloudClient(
            session: session,
            baseURL: URL(string: "https://developer-api.govee.com")!,
            apiKeyProvider: { "test-key" }
        )
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("Request handler is not set")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
