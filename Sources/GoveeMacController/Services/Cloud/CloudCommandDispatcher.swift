import Foundation

actor CloudCommandDispatcher {
    typealias Sender = @Sendable (Device, ControlCommand) async throws -> Void

    private let sender: Sender
    private let minIntervalNanoseconds: UInt64

    private var latestCommandByKey: [String: ControlCommand] = [:]
    private var waitingContinuations: [String: [CheckedContinuation<Void, Error>]] = [:]
    private var activeWorkers: [String: Task<Void, Never>] = [:]

    init(minInterval: TimeInterval = 0.12, sender: @escaping Sender) {
        self.sender = sender
        self.minIntervalNanoseconds = UInt64(max(minInterval, 0) * 1_000_000_000)
    }

    func submit(device: Device, command: ControlCommand) async throws {
        let key = "\(device.id)::\(command.coalescingKey)"

        try await withCheckedThrowingContinuation { continuation in
            waitingContinuations[key, default: []].append(continuation)
            latestCommandByKey[key] = command

            if activeWorkers[key] == nil {
                activeWorkers[key] = Task {
                    await runWorker(for: key, device: device)
                }
            }
        }
    }

    private func runWorker(for key: String, device: Device) async {
        var caughtError: Error?

        while true {
            guard let next = latestCommandByKey[key] else {
                break
            }

            latestCommandByKey[key] = nil

            do {
                try await sender(device, next)
                if minIntervalNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: minIntervalNanoseconds)
                }
            } catch {
                caughtError = error
                break
            }
        }

        let continuations = waitingContinuations.removeValue(forKey: key) ?? []
        for continuation in continuations {
            if let caughtError {
                continuation.resume(throwing: caughtError)
            } else {
                continuation.resume(returning: ())
            }
        }

        activeWorkers[key] = nil
    }
}
