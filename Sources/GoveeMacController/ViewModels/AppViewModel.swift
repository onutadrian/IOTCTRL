import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var apiKeyInput: String = ""
    @Published var hasAPIKey: Bool = false
    @Published var devices: [Device] = []
    @Published var selectedDeviceID: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let container: DependencyContainer
    private let repository: DeviceRepository
    private let controller: DeviceController
    private let credentialsStore: CredentialsStore
    private let manualLANIPStoreKey = "manual-lan-ip-overrides"
    private let stateRequestSpacingNanoseconds: UInt64 = 700_000_000
    private var manualLANIPOverrides: [String: String]

    init(container: DependencyContainer = DependencyContainer()) {
        self.container = container
        self.repository = container.deviceRepository
        self.controller = container.deviceController
        self.credentialsStore = container.credentialsStore
        self.manualLANIPOverrides = UserDefaults.standard.dictionary(forKey: manualLANIPStoreKey) as? [String: String] ?? [:]
        self.hasAPIKey = container.credentialsStore.loadAPIKey() != nil
    }

    var selectedDevice: Device? {
        guard let selectedDeviceID else {
            return devices.first
        }
        return devices.first(where: { $0.id == selectedDeviceID })
    }

    func bootstrap() {
        hasAPIKey = credentialsStore.loadAPIKey() != nil
        if hasAPIKey {
            Task {
                await refreshDevices()
            }
        }
    }

    func saveAPIKey() {
        do {
            try credentialsStore.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            hasAPIKey = true
            Task {
                await refreshDevices()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearAPIKey() {
        credentialsStore.clearAPIKey()
        hasAPIKey = false
        devices = []
        selectedDeviceID = nil
    }

    func refreshDevices() async {
        guard hasAPIKey else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await repository.fetchDevices()
            let withManualOverrides = applyManualLANIPOverrides(to: loaded)
            let hydrated = await hydrateDeviceStates(for: withManualOverrides)

            devices = hydrated
            if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = devices.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPower(_ value: Bool, for device: Device) {
        performOptimisticCommand(command: .power(value), device: device) { mutable in
            mutable.isOn = value
        }
    }

    func setBrightness(_ value: Int, for device: Device) {
        performOptimisticCommand(command: .brightness(value), device: device) { mutable in
            mutable.brightness = min(max(value, 0), 100)
        }
    }

    func setColor(_ value: RGBColor, for device: Device) {
        performOptimisticCommand(command: .color(value), device: device) { mutable in
            mutable.color = value
        }
    }

    func setColorTemp(_ value: Int, for device: Device) {
        performOptimisticCommand(command: .colorTemp(value), device: device) { mutable in
            mutable.colorTemp = value
        }
    }

    func triggerScene(_ sceneID: String, for device: Device) {
        performOptimisticCommand(command: .scene(sceneID), device: device) { _ in }
    }

    func transportLabel(for device: Device, command: ControlCommand) -> String {
        guard let transport = controller.preferredTransport(for: device, command: command) else {
            return "N/A"
        }
        return transport.rawValue
    }

    func manualLANIP(for device: Device) -> String {
        manualLANIPOverrides[device.id] ?? ""
    }

    func saveManualLANIP(_ ip: String, for device: Device) {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearManualLANIP(for: device)
            return
        }

        manualLANIPOverrides[device.id] = trimmed
        UserDefaults.standard.set(manualLANIPOverrides, forKey: manualLANIPStoreKey)
        applyManualLANIPOverrideOnCurrentList(deviceID: device.id, ip: trimmed)
    }

    func clearManualLANIP(for device: Device) {
        manualLANIPOverrides.removeValue(forKey: device.id)
        UserDefaults.standard.set(manualLANIPOverrides, forKey: manualLANIPStoreKey)
        Task {
            await refreshDevices()
        }
    }

    private func applyManualLANIPOverrides(to input: [Device]) -> [Device] {
        input.map { device in
            guard let overrideIP = manualLANIPOverrides[device.id], !overrideIP.isEmpty else {
                return device
            }

            var mutable = device
            mutable.ip = overrideIP
            mutable.capabilities.lanSupported = true
            mutable.isManualLANOverride = true
            if mutable.transportProfile == .cloud {
                mutable.transportProfile = .hybrid
            }
            return mutable
        }
    }

    private func applyManualLANIPOverrideOnCurrentList(deviceID: String, ip: String) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else {
            return
        }

        var mutable = devices[index]
        mutable.ip = ip
        mutable.capabilities.lanSupported = true
        mutable.isManualLANOverride = true
        if mutable.transportProfile == .cloud {
            mutable.transportProfile = .hybrid
        }
        devices[index] = mutable
    }

    private func performOptimisticCommand(
        command: ControlCommand,
        device: Device,
        mutate: @escaping (inout Device) -> Void
    ) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else {
            return
        }

        let previous = devices[index]
        var next = previous
        mutate(&next)
        devices[index] = next

        let controller = self.controller
        Task {
            do {
                try await controller.send(command, to: next)
                if case .power(let isOn) = command, isOn {
                    await self.syncStateAfterPowerOn(deviceID: device.id)
                }
            } catch {
                await MainActor.run {
                    if let rollbackIndex = self.devices.firstIndex(where: { $0.id == device.id }) {
                        self.devices[rollbackIndex] = previous
                    }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func hydrateDeviceStates(for input: [Device]) async -> [Device] {
        guard !input.isEmpty else {
            return input
        }

        var hydrated = input
        let lastIndex = hydrated.indices.last

        for index in hydrated.indices {
            let device = hydrated[index]
            guard shouldRequestCloudState(for: device) else {
                continue
            }

            if let state = await fetchCloudState(for: device, maxAttempts: 2) {
                applyCloudState(state, to: &hydrated[index])
            }

            if let lastIndex, index != lastIndex {
                try? await Task.sleep(nanoseconds: stateRequestSpacingNanoseconds)
            }
        }

        return hydrated
    }

    private func shouldRequestCloudState(for device: Device) -> Bool {
        if device.transportProfile == .lan {
            return false
        }

        if device.model.caseInsensitiveCompare("Unknown") == .orderedSame {
            return false
        }

        if let isOn = device.isOn {
            if !isOn {
                return false
            }

            if device.brightness != nil {
                return false
            }
        }

        return true
    }

    private func fetchCloudState(for device: Device, maxAttempts: Int) async -> CloudDeviceState? {
        guard maxAttempts > 0 else {
            return nil
        }

        for attempt in 0 ..< maxAttempts {
            do {
                return try await container.cloudClient.getState(deviceID: device.id, model: device.model)
            } catch let AppError.rateLimited(retryAfter) {
                let waitSeconds = max(retryAfter, 0.9)
                try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
            } catch AppError.networkFailure(_) where attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return nil
            }
        }

        return nil
    }

    private func syncStateAfterPowerOn(deviceID: String) async {
        guard let startIndex = devices.firstIndex(where: { $0.id == deviceID }) else {
            return
        }

        let current = devices[startIndex]
        guard shouldRequestCloudState(for: current) else {
            return
        }

        let pollDelays: [UInt64] = [700_000_000, 1_500_000_000]
        var latestState: CloudDeviceState?

        for delay in pollDelays {
            try? await Task.sleep(nanoseconds: delay)

            guard let refreshed = devices.first(where: { $0.id == deviceID }) else {
                return
            }

            if let state = await fetchCloudState(for: refreshed, maxAttempts: 1) {
                latestState = state
                if state.brightness != nil || state.isOn == false {
                    break
                }
            }
        }

        guard let state = latestState,
              let updateIndex = devices.firstIndex(where: { $0.id == deviceID })
        else {
            return
        }

        var mutable = devices[updateIndex]
        applyCloudState(state, to: &mutable)
        devices[updateIndex] = mutable
    }

    private func applyCloudState(_ state: CloudDeviceState, to device: inout Device) {
        if let isOnline = state.isOnline {
            device.isOnline = isOnline
        }
        if let isOn = state.isOn {
            device.isOn = isOn
        }
        if let brightness = state.brightness {
            device.brightness = min(max(brightness, 0), 100)
        }
        if let color = state.color {
            device.color = color
        }
        if let colorTemp = state.colorTemp {
            device.colorTemp = colorTemp
        }
    }
}
