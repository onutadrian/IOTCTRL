import AppKit
import SwiftUI

struct DeviceDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    let device: Device?

    @State private var manualIPDraft: String = ""
    @State private var showingSettings = false
    @State private var brightnessDraft: Double?
    @State private var saveHovered = false
    @State private var pasteHovered = false
    @FocusState private var manualIPFocused: Bool

    var body: some View {
        Group {
            if let device {
                VStack(alignment: .leading, spacing: 12) {
                    if showingSettings {
                        settingsCard(device)
                    } else {
                        controlCard(device)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No Device Selected")
                        .font(.headline)
                    Text("Pick a device from the list to start controlling it.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(figmaBackground.ignoresSafeArea())
        .animation(.snappy(duration: 0.2), value: showingSettings)
        .onAppear {
            showingSettings = false
            syncManualIPDraft(force: true)
            brightnessDraft = nil
        }
        .onChange(of: device?.id) { _ in
            showingSettings = false
            syncManualIPDraft(force: true)
            brightnessDraft = nil
        }
    }

    @ViewBuilder
    private func controlCard(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                VStack {
                    Spacer(minLength: 0)
                    powerButton(for: device)
                    Spacer(minLength: 0)
                }
                .frame(width: 44)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        transportBadge(for: device)
                        Spacer(minLength: 8)
                        Button {
                            showingSettings = true
                            syncManualIPDraft(force: true)
                            manualIPFocused = false
                        } label: {
                            figmaIcon("icon_settings", width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.name.uppercased())
                            .font(.figmaMonoMedium(size: 14))
                            .tracking(0.4)
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text("MODEL:")
                            Text(device.model.uppercased())
                        }
                        .font(.figmaMonoRegular(size: 10))
                        .tracking(0.6)
                        .foregroundStyle(Color.figmaSecondary)
                    }

                    if device.capabilities.canBrightness {
                        brightnessRow(for: device)
                            .opacity(device.isOn == false ? 0.35 : 1.0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .frame(width: 300, height: 167, alignment: .topLeading)
        .background(cardBackground)
    }

    @ViewBuilder
    private func settingsCard(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    manualIPFocused = false
                    showingSettings = false
                } label: {
                    figmaIcon("icon_back", width: 16, height: 16)
                }
                .buttonStyle(.plain)

                Text("MNL IP FLBK")
                    .font(.figmaMonoMedium(size: 14))
                    .tracking(0.4)
                    .foregroundStyle(Color.white)

                HStack(spacing: 4) {
                    Text("MNL OVRD")
                        .foregroundStyle(Color.figmaAlert)
                    Text("ENTR DHCP IP")
                        .foregroundStyle(Color.figmaSecondary)
                }
                .font(.figmaMonoRegular(size: 10))
                .tracking(0.6)
            }

            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("168.0.0.12", text: $manualIPDraft)
                        .textFieldStyle(.plain)
                        .font(.figmaMonoMedium(size: 14))
                        .foregroundStyle(Color.white)
                        .focused($manualIPFocused)
                        .onSubmit {
                            applyManualIP(manualIPDraft, for: device)
                            manualIPFocused = false
                            syncManualIPDraft(force: true)
                        }

                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(height: 1)
                }

                Button {
                    manualIPDraft = ""
                    viewModel.clearManualLANIP(for: device)
                    manualIPFocused = false
                } label: {
                    figmaIcon("icon_clear", width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                Button {
                    applyManualIP(manualIPDraft, for: device)
                    manualIPFocused = false
                    syncManualIPDraft(force: true)
                } label: {
                    figmaTextButton(
                        "SAVE",
                        idleIcon: "icon_shield_idle",
                        hoverIcon: "icon_shield_hover",
                        isHovered: saveHovered
                    )
                }
                .buttonStyle(.plain)
                .background(saveHovered ? Color.figmaButtonHover : Color.clear)
                .onHover { saveHovered = $0 }

                Button {
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        let firstLine = clipboard
                            .components(separatedBy: .newlines)
                            .first?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard !firstLine.isEmpty else {
                            return
                        }
                        manualIPDraft = firstLine
                        applyManualIP(firstLine, for: device)
                        manualIPFocused = false
                        syncManualIPDraft(force: true)
                    }
                } label: {
                    figmaTextButton(
                        "PASTE IP",
                        idleIcon: "icon_clipboard_idle",
                        hoverIcon: "icon_clipboard_hover",
                        isHovered: pasteHovered
                    )
                }
                .buttonStyle(.plain)
                .background(pasteHovered ? Color.figmaButtonHover : Color.clear)
                .onHover { pasteHovered = $0 }
            }
        }
        .padding(16)
        .frame(width: 232, height: 167, alignment: .topLeading)
        .background(cardBackground)
        .onAppear {
            syncManualIPDraft(force: true)
        }
    }

    @ViewBuilder
    private func brightnessRow(for device: Device) -> some View {
        let current = brightnessDraft ?? Double(device.brightness ?? 0)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(current.rounded()))%")
                .font(.figmaMonoMedium(size: 10))
                .tracking(0.3)
                .foregroundStyle(Color.figmaSecondary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 6) {
                figmaIcon("icon_brightness_min", width: 12, height: 12)

                BrightnessTrack(value: current) { draft in
                    brightnessDraft = draft
                } onCommit: { committed in
                    brightnessDraft = committed
                    viewModel.setBrightness(Int(committed.rounded()), for: device)
                }
                .frame(height: 10)

                figmaIcon("icon_brightness_max", width: 24, height: 24)
            }
        }
    }

    @ViewBuilder
    private func powerButton(for device: Device) -> some View {
        let isOn = device.isOn ?? false
        let canPower = device.capabilities.canPower
        Button {
            guard canPower else {
                return
            }
            viewModel.setPower(!isOn, for: device)
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0x1F / 255.0, green: 0x1F / 255.0, blue: 0x1F / 255.0), Color(red: 0x2C / 255.0, green: 0x2A / 255.0, blue: 0x2A / 255.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.65), lineWidth: 1)
                )
                .overlay(
                    figmaIcon(isOn ? "power_on" : "power_off", width: 24, height: 24)
                        .opacity(canPower ? 1 : 0.6)
                )
                .frame(width: 43.5, height: 43.5)
        }
        .buttonStyle(.plain)
        .disabled(!canPower)
        .opacity(canPower ? 1 : 0.45)
    }

    @ViewBuilder
    private func transportBadge(for device: Device) -> some View {
        let (bg, fg, label): (Color, Color, String) = {
            if let isOnline = device.isOnline, !isOnline {
                return (Color.figmaOfflineBadgeBackground, Color.figmaSecondary, "OFFLINE")
            }

            switch device.transportProfile {
            case .hybrid:
                return (Color.figmaHybridBadgeBackground, Color.figmaHybridBadgeForeground, "HYBRID")
            case .lan:
                return (Color.figmaLanBadgeBackground, Color.figmaLanBadgeForeground, "LAN")
            case .cloud:
                return (Color.figmaCloudBadgeBackground, Color.figmaCloudBadgeForeground, "CLOUD")
            }
        }()

        Text(label)
            .font(.figmaMonoRegular(size: 10))
            .tracking(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(fg)
            .background(bg)
    }

    @ViewBuilder
    private func figmaTextButton(
        _ title: String,
        idleIcon: String,
        hoverIcon: String,
        isHovered: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.figmaMonoMedium(size: 10))
                .tracking(0.3)
                .foregroundStyle(Color.white)
            figmaIcon(isHovered ? hoverIcon : idleIcon, width: 16, height: 16)
        }
        .padding(4)
    }

    @ViewBuilder
    private func figmaIcon(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        if let image = FigmaResources.image(named: name) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: width, height: height)
        } else {
            Color.clear
                .frame(width: width, height: height)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 40, style: .continuous)
            .fill(Color.figmaCard)
            .overlay(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            )
    }

    private var figmaBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.12, blue: 0.13),
                Color(red: 0.09, green: 0.09, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func syncManualIPDraft(force: Bool = false) {
        guard force || !manualIPFocused else {
            return
        }
        guard let device else {
            manualIPDraft = ""
            return
        }
        manualIPDraft = viewModel.manualLANIP(for: device)
    }

    private func applyManualIP(_ value: String, for device: Device) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelyIPv4(trimmed) else {
            viewModel.errorMessage = "Invalid IP. Use format like 192.168.0.224."
            return
        }
        viewModel.saveManualLANIP(trimmed, for: device)
    }

    private func isLikelyIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return false
        }

        for part in parts {
            guard let octet = Int(part), (0 ... 255).contains(octet) else {
                return false
            }
        }
        return true
    }
}

private struct BrightnessTrack: View {
    let value: Double
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black)
                    .frame(height: 4)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.45)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * CGFloat(clamped / 100), height: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onChange(positionToValue(gesture.location.x, width: width))
                    }
                    .onEnded { gesture in
                        let next = positionToValue(gesture.location.x, width: width)
                        onChange(next)
                        onCommit(next)
                    }
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var clamped: Double {
        min(max(value, 0), 100)
    }

    private func positionToValue(_ x: CGFloat, width: CGFloat) -> Double {
        let normalized = min(max(x / width, 0), 1)
        return Double(normalized * 100)
    }
}

private extension Color {
    static let figmaCard = Color(red: 0x27 / 255.0, green: 0x25 / 255.0, blue: 0x25 / 255.0)
    static let figmaSecondary = Color(red: 0x8F / 255.0, green: 0x8F / 255.0, blue: 0x8F / 255.0)
    static let figmaPowerOn = Color(red: 0xF4 / 255.0, green: 0xE3 / 255.0, blue: 0x17 / 255.0)
    static let figmaPowerOff = Color(red: 0x8F / 255.0, green: 0x8F / 255.0, blue: 0x8F / 255.0)
    static let figmaAlert = Color(red: 0xFF / 255.0, green: 0x4B / 255.0, blue: 0x4B / 255.0)
    static let figmaButtonHover = Color(red: 0x7E / 255.0, green: 0x7B / 255.0, blue: 0x7B / 255.0)

    static let figmaHybridBadgeBackground = Color(red: 0xF4 / 255.0, green: 0xB5 / 255.0, blue: 0x17 / 255.0)
    static let figmaHybridBadgeForeground = Color(red: 0x62 / 255.0, green: 0x46 / 255.0, blue: 0x00 / 255.0)

    static let figmaCloudBadgeBackground = Color(red: 0x22 / 255.0, green: 0x65 / 255.0, blue: 0xD4 / 255.0)
    static let figmaCloudBadgeForeground = Color(red: 0xE1 / 255.0, green: 0xEC / 255.0, blue: 0xFF / 255.0)

    static let figmaLanBadgeBackground = Color(red: 0xB0 / 255.0, green: 0xD4 / 255.0, blue: 0x22 / 255.0)
    static let figmaLanBadgeForeground = Color(red: 0x44 / 255.0, green: 0x55 / 255.0, blue: 0x00 / 255.0)

    static let figmaOfflineBadgeBackground = Color(red: 0x3A / 255.0, green: 0x39 / 255.0, blue: 0x39 / 255.0)
}
