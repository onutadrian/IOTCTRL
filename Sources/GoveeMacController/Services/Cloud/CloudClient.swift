import Foundation

struct CloudDevice: Sendable {
    let id: String
    let model: String
    let name: String
    let mac: String
    let supportCommands: Set<String>
    let isOnline: Bool?
}

struct CloudDeviceState: Sendable {
    var isOnline: Bool?
    var isOn: Bool?
    var brightness: Int?
    var color: RGBColor?
    var colorTemp: Int?
}

actor CloudClient {
    private let session: URLSession
    private let baseURL: URL
    private let apiKeyProvider: () -> String?

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://developer-api.govee.com")!,
        apiKeyProvider: @escaping () -> String?
    ) {
        self.session = session
        self.baseURL = baseURL
        self.apiKeyProvider = apiKeyProvider
    }

    func listDevices() async throws -> [CloudDevice] {
        let url = baseURL.appendingPathComponent("v1/devices")
        let request = try makeRequest(url: url, method: "GET")
        let response: DeviceListResponse = try await performDecodable(request, as: DeviceListResponse.self)

        return response.data.devices.map { dto in
            let supportCommands = Set(dto.supportCmds.map { $0.lowercased() })
            return CloudDevice(
                id: dto.device,
                model: dto.model,
                name: dto.deviceName ?? dto.model,
                mac: dto.device,
                supportCommands: supportCommands,
                isOnline: nil
            )
        }
    }

    func getState(deviceID: String, model: String) async throws -> CloudDeviceState {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/devices/state"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "device", value: deviceID),
            URLQueryItem(name: "model", value: model)
        ]

        guard let url = components?.url else {
            throw AppError.malformedResponse
        }

        let request = try makeRequest(url: url, method: "GET")
        let response: DeviceStateEnvelope = try await performDecodable(request, as: DeviceStateEnvelope.self)

        var state = CloudDeviceState()
        for property in response.data.properties {
            let key = normalizedPropertyKey(property.name)
            let rawValue = property.rawValue

            switch key {
            case "powerstate", "turn", "powerswitch", "power", "switch", "onoff":
                if let isOn = parseBoolValue(rawValue) {
                    state.isOn = isOn
                }
            case "online", "isonline":
                if let isOnline = parseBoolValue(rawValue) {
                    state.isOnline = isOnline
                }
            case "brightness":
                if let brightness = parseIntValue(rawValue) {
                    state.brightness = min(max(brightness, 0), 100)
                }
            case "colortem", "colortemp", "colorteminkelvin", "colortempinkelvin":
                if let colorTemp = parseIntValue(rawValue) {
                    state.colorTemp = colorTemp
                }
            case "color", "rgb":
                if let color = parseRGBColor(rawValue) {
                    state.color = color
                }
            default:
                continue
            }
        }

        return state
    }

    func control(deviceID: String, model: String, command: ControlCommand) async throws {
        let url = baseURL.appendingPathComponent("v1/devices/control")
        let body = CloudControlBody(
            device: deviceID,
            model: model,
            cmd: command.cloudPayload
        )

        let request = try makeRequest(url: url, method: "PUT", body: body)
        _ = try await performWithoutBody(request)
    }

    private func makeRequest(url: URL, method: String) throws -> URLRequest {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw AppError.missingAPIKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Govee-API-Key")
        request.timeoutInterval = 12

        return request
    }

    private func makeRequest<T: Encodable>(url: URL, method: String, body: T) throws -> URLRequest {
        var request = try makeRequest(url: url, method: method)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func performWithoutBody(_ request: URLRequest) async throws -> HTTPURLResponse {
        let (_, response) = try await performRaw(request)
        return response
    }

    private func performDecodable<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, _) = try await performRaw(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AppError.networkFailure("Failed to decode response: \(error.localizedDescription)")
        }
    }

    private func performRaw(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.networkFailure(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkFailure("Non-HTTP response")
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            return (data, httpResponse)
        case 401, 403:
            throw AppError.unauthorized
        case 429:
            let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After")
            let retryAfter = retryAfterHeader.flatMap(Double.init) ?? 1
            throw AppError.rateLimited(retryAfter: retryAfter)
        default:
            let responseBody = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AppError.networkFailure("HTTP \(httpResponse.statusCode): \(responseBody)")
        }
    }
}

final class CloudTransport: CommandTransport, @unchecked Sendable {
    let kind: TransportKind = .cloud

    private let client: CloudClient
    private let dispatcher: CloudCommandDispatcher

    init(client: CloudClient, minInterval: TimeInterval = 0.12) {
        self.client = client
        self.dispatcher = CloudCommandDispatcher(minInterval: minInterval) { [client] device, command in
            try await CloudTransport.sendWithRetry(client: client, device: device, command: command)
        }
    }

    func canHandle(command: ControlCommand, for device: Device) -> Bool {
        device.capabilities.supports(command, via: .cloud)
    }

    func send(_ command: ControlCommand, to device: Device) async throws {
        guard canHandle(command: command, for: device) else {
            throw AppError.unsupportedCommand(command: command, device: device.name)
        }

        try await dispatcher.submit(device: device, command: command)
    }

    private static func sendWithRetry(client: CloudClient, device: Device, command: ControlCommand) async throws {
        var lastError: Error?
        for attempt in 0 ..< 3 {
            do {
                try await client.control(deviceID: device.id, model: device.model, command: command)
                return
            } catch let error as AppError {
                lastError = error
                if case .rateLimited(let retryAfter) = error {
                    let delaySeconds = max(retryAfter, Double(attempt + 1))
                    try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    continue
                }
                throw error
            } catch {
                lastError = error
                throw error
            }
        }

        throw lastError ?? AppError.networkFailure("Command failed after retries")
    }
}

private struct DeviceListResponse: Decodable {
    let data: DeviceListData
}

private struct DeviceListData: Decodable {
    let devices: [DeviceDTO]
}

private struct DeviceDTO: Decodable {
    let device: String
    let model: String
    let deviceName: String?
    let supportCmds: [String]

    enum CodingKeys: String, CodingKey {
        case device
        case model
        case deviceName
        case supportCmds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = try container.decode(String.self, forKey: .device)
        model = try container.decode(String.self, forKey: .model)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)

        let entries = (try? container.decode([SupportCommandEntry].self, forKey: .supportCmds)) ?? []
        supportCmds = entries.map(\.name)
    }
}

private struct CommandObject: Decodable {
    let name: String
}

private enum SupportCommandEntry: Decodable {
    case string(String)
    case object(CommandObject)

    var name: String {
        switch self {
        case .string(let value):
            return value
        case .object(let object):
            return object.name
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        if let object = try? container.decode(CommandObject.self) {
            self = .object(object)
            return
        }

        throw DecodingError.typeMismatch(
            SupportCommandEntry.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported supportCmds entry")
        )
    }
}

private struct DeviceStateEnvelope: Decodable {
    let data: DeviceStateData
}

private struct DeviceStateData: Decodable {
    let properties: [DeviceProperty]
}

private struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    init(_ value: String) {
        stringValue = value
        intValue = nil
    }
}

private struct DeviceProperty: Decodable {
    let name: String
    let rawValue: Any?
    let valueInt: Int?
    let valueString: String?
    let objectValue: [String: Any]?

    init(name: String, rawValue: Any?) {
        self.name = name
        self.rawValue = rawValue
        self.valueInt = parseIntValue(rawValue)

        if let stringValue = rawValue as? String {
            self.valueString = stringValue
        } else if let intValue = rawValue as? Int {
            self.valueString = String(intValue)
        } else if let doubleValue = rawValue as? Double {
            self.valueString = String(doubleValue)
        } else if let boolValue = rawValue as? Bool {
            self.valueString = boolValue ? "true" : "false"
        } else {
            self.valueString = nil
        }

        self.objectValue = rawValue as? [String: Any]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let nameKey = DynamicCodingKey("name")
        let valueKey = DynamicCodingKey("value")

        if container.contains(nameKey),
           container.contains(valueKey),
           let decodedName = try? container.decode(String.self, forKey: nameKey) {
            let decodedValue = Self.decodeAny(from: container, forKey: valueKey)
            self.init(name: decodedName, rawValue: decodedValue)
            return
        }

        if let singleKey = container.allKeys.first {
            let decodedValue = Self.decodeAny(from: container, forKey: singleKey)
            self.init(name: singleKey.stringValue, rawValue: decodedValue)
            return
        }

        self.init(name: "", rawValue: nil)
    }

    private static func decodeAny(from container: KeyedDecodingContainer<DynamicCodingKey>, forKey key: DynamicCodingKey) -> Any? {
        if let boolValue = try? container.decode(Bool.self, forKey: key) {
            return boolValue
        }

        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue
        }

        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return doubleValue
        }

        if let stringValue = try? container.decode(String.self, forKey: key) {
            return stringValue
        }

        if let objectValue = try? container.decode([String: JSONAnyCodable].self, forKey: key) {
            var converted: [String: Any] = [:]
            for (objectKey, value) in objectValue {
                converted[objectKey] = value.value
            }
            return converted
        }

        if let arrayValue = try? container.decode([JSONAnyCodable].self, forKey: key) {
            return arrayValue.map(\.value)
        }

        return nil
    }
}

private struct CloudControlBody: Encodable {
    let device: String
    let model: String
    let cmd: CloudCommandPayload
}

private struct CloudCommandPayload: Encodable {
    let name: String
    let value: JSONEncodableValue
}

private enum JSONEncodableValue: Encodable {
    case string(String)
    case int(Int)
    case object([String: JSONEncodableValue])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let object):
            var container = encoder.singleValueContainer()
            try container.encode(object)
        }
    }
}

private struct JSONAnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([JSONAnyCodable].self) {
            value = arrayValue.map(\.value)
        } else if let dictValue = try? container.decode([String: JSONAnyCodable].self) {
            var converted: [String: Any] = [:]
            for (key, value) in dictValue {
                converted[key] = value.value
            }
            value = converted
        } else {
            value = NSNull()
        }
    }
}

private func normalizedPropertyKey(_ raw: String) -> String {
    raw
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
}

private func parseBoolValue(_ raw: Any?) -> Bool? {
    guard let raw else {
        return nil
    }

    if let value = raw as? Bool {
        return value
    }

    if let number = raw as? NSNumber {
        return number.intValue != 0
    }

    if let value = raw as? String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["on", "true", "1", "yes"].contains(normalized) {
            return true
        }
        if ["off", "false", "0", "no"].contains(normalized) {
            return false
        }
        return nil
    }

    if let object = raw as? [String: Any] {
        return parseBoolValue(object["value"])
    }

    return nil
}

private func parseIntValue(_ raw: Any?) -> Int? {
    guard let raw else {
        return nil
    }

    if let value = raw as? Int {
        return value
    }

    if let value = raw as? Double {
        return Int(value.rounded())
    }

    if let number = raw as? NSNumber {
        return number.intValue
    }

    if let value = raw as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        if let intValue = Int(trimmed) {
            return intValue
        }
        if let doubleValue = Double(trimmed) {
            return Int(doubleValue.rounded())
        }
        return nil
    }

    if let object = raw as? [String: Any] {
        return parseIntValue(object["value"])
    }

    return nil
}

private func parseRGBColor(_ raw: Any?) -> RGBColor? {
    guard let raw else {
        return nil
    }

    guard let object = raw as? [String: Any] else {
        return nil
    }

    let payload: [String: Any]
    if let nested = object["value"] as? [String: Any] {
        payload = nested
    } else {
        payload = object
    }

    guard let r = parseIntValue(payload["r"]),
          let g = parseIntValue(payload["g"]),
          let b = parseIntValue(payload["b"])
    else {
        return nil
    }

    return RGBColor(r: r, g: g, b: b)
}

private extension ControlCommand {
    var cloudPayload: CloudCommandPayload {
        switch self {
        case .power(let isOn):
            return CloudCommandPayload(name: "turn", value: .string(isOn ? "on" : "off"))
        case .brightness(let value):
            return CloudCommandPayload(name: "brightness", value: .int(min(max(value, 0), 100)))
        case .color(let rgb):
            return CloudCommandPayload(
                name: "color",
                value: .object([
                    "r": .int(rgb.r),
                    "g": .int(rgb.g),
                    "b": .int(rgb.b)
                ])
            )
        case .colorTemp(let kelvin):
            return CloudCommandPayload(name: "colorTem", value: .int(max(kelvin, 2000)))
        case .scene(let sceneId):
            return CloudCommandPayload(name: "scene", value: .string(sceneId))
        }
    }
}
