import Foundation

enum AppError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case unsupportedCommand(command: ControlCommand, device: String)
    case missingLANAddress(device: String)
    case transportUnavailable(device: String)
    case malformedResponse
    case networkFailure(String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a Govee API key before loading devices."
        case .invalidAPIKey:
            return "The Govee API key looks invalid."
        case .unsupportedCommand(_, let device):
            return "This command is not supported for \(device)."
        case .missingLANAddress(let device):
            return "LAN control is unavailable for \(device) because no local IP was discovered."
        case .transportUnavailable(let device):
            return "No valid transport is available for \(device)."
        case .malformedResponse:
            return "Received malformed data from Govee."
        case .networkFailure(let message):
            return "Network request failed: \(message)"
        case .unauthorized:
            return "Unauthorized. Verify your Govee API key."
        case .rateLimited(let retryAfter):
            return "Govee rate limit reached. Retry in \(Int(retryAfter)) seconds."
        }
    }
}
