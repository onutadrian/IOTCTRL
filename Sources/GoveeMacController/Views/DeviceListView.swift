import AppKit
import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(Color.clear)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("GOVEE LIGHTS CTRLR")
                        .font(.figmaMonoMedium(size: 10))
                        .tracking(0.3)
                        .foregroundStyle(Color.white)
                    Spacer()
                    HStack(spacing: 10) {
                        actionButton(title: "REFRESH", systemIcon: "arrow.clockwise") {
                            Task { await viewModel.refreshDevices() }
                        }
                        actionButton(title: "CLOSE", figmaIconName: "icon_clear") {
                            NSApp.terminate(nil)
                        }
                    }
                }
                .padding(10)
                .frame(height: 44)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(299.498), spacing: 8),
                            GridItem(.fixed(299.498), spacing: 8)
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        if viewModel.isLoading {
                            let skeletonCount = max(viewModel.devices.count, 4)

                            ForEach(0..<skeletonCount, id: \.self) { _ in
                                DeviceCardSkeletonView()
                            }
                        } else {
                            ForEach(viewModel.devices) { device in
                                DeviceGridCardView(viewModel: viewModel, device: device)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(8)
        }
        .padding(8)
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemIcon: String? = nil,
        figmaIconName: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.figmaMonoMedium(size: 10))
                    .tracking(0.3)
                    .foregroundStyle(Color.white)

                if let figmaIconName {
                    if let image = FigmaResources.image(named: figmaIconName) {
                        Image(nsImage: image)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    } else {
                        Color.clear.frame(width: 16, height: 16)
                    }
                } else if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(red: 0x8F / 255.0, green: 0x8F / 255.0, blue: 0x8F / 255.0))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(4)
        }
        .buttonStyle(.plain)
    }
}

private struct DeviceGridCardView: View {
    @ObservedObject var viewModel: AppViewModel
    let device: Device

    @State private var brightnessDraft: Double?
    @State private var showingSettings = false
    @State private var manualIPDraft: String = ""
    @State private var saveHovered = false
    @State private var pasteHovered = false
    @FocusState private var manualIPFocused: Bool

    var body: some View {
        ZStack {
            frontFace
                .rotation3DEffect(
                    .degrees(showingSettings ? -90 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.65
                )
                .opacity(showingSettings ? 0 : 1)

            settingsFace
                .rotation3DEffect(
                    .degrees(showingSettings ? 0 : 90),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.65
                )
                .opacity(showingSettings ? 1 : 0)
        }
        .frame(width: 299.498, height: 167, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Color(red: 0x27 / 255.0, green: 0x25 / 255.0, blue: 0x25 / 255.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.35), value: showingSettings)
        .onAppear {
            manualIPDraft = viewModel.manualLANIP(for: device)
        }
        .onChange(of: device.id) { _ in
            showingSettings = false
            manualIPDraft = viewModel.manualLANIP(for: device)
            brightnessDraft = nil
        }
        .onChange(of: device.brightness) { _ in
            if !showingSettings {
                brightnessDraft = nil
            }
        }
    }

    private var frontFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                VStack {
                    Spacer(minLength: 0)
                    powerButton
                    Spacer(minLength: 0)
                }
                .frame(width: 43.498)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            transportBadge
                            Spacer(minLength: 8)
                            Button {
                                manualIPDraft = viewModel.manualLANIP(for: device)
                                manualIPFocused = false
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    showingSettings = true
                                }
                            } label: {
                                figmaIcon("icon_settings", width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(device.name.uppercased())
                            .font(.figmaMonoMedium(size: 14))
                            .tracking(0.42)
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Text("MODEL:")
                        Text(device.model.uppercased())
                    }
                    .font(.figmaMonoRegular(size: 10))
                    .tracking(0.6)
                    .foregroundStyle(Color(red: 0x8F / 255.0, green: 0x8F / 255.0, blue: 0x8F / 255.0))
                    .padding(.top, 8)

                    Spacer(minLength: 0)

                    if device.capabilities.canBrightness {
                        brightnessRow
                            .opacity(device.isOn == false ? 0.35 : 1.0)
                    }
                }
                .frame(width: 184, height: 119, alignment: .topLeading)
            }
            .padding(16)
        }
    }

    private var settingsFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                manualIPFocused = false
                withAnimation(.easeInOut(duration: 0.35)) {
                    showingSettings = false
                }
            } label: {
                figmaIcon("icon_back", width: 16, height: 16)
            }
            .buttonStyle(.plain)

            Text("MNL IP FLBK")
                .font(.figmaMonoMedium(size: 14))
                .tracking(0.42)
                .foregroundStyle(Color.white)

            HStack(spacing: 4) {
                Text("MNL OVRD")
                    .font(.figmaMonoRegular(size: 10))
                    .tracking(0.6)
                    .foregroundStyle(Color(red: 0xFF / 255.0, green: 0x4B / 255.0, blue: 0x4B / 255.0))
                Text("ENTR DHCP IP")
                    .font(.figmaMonoRegular(size: 10))
                    .tracking(0.6)
                    .foregroundStyle(Color(red: 0x8F / 255.0, green: 0x8F / 255.0, blue: 0x8F / 255.0))
            }

            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("168.0.0.12", text: $manualIPDraft)
                        .textFieldStyle(.plain)
                        .font(.figmaMonoMedium(size: 14))
                        .foregroundStyle(Color.white)
                        .focused($manualIPFocused)
                        .onSubmit {
                            applyManualIP(manualIPDraft)
                            manualIPFocused = false
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
                    applyManualIP(manualIPDraft)
                    manualIPFocused = false
                } label: {
                    figmaSettingsButton(
                        title: "SAVE",
                        idleIcon: "icon_shield_idle",
                        hoverIcon: "icon_shield_hover",
                        isHovered: saveHovered
                    )
                }
                .buttonStyle(.plain)
                .background(saveHovered ? Color(red: 0x7E / 255.0, green: 0x7B / 255.0, blue: 0x7B / 255.0) : Color.clear)
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
                        applyManualIP(firstLine)
                        manualIPFocused = false
                    }
                } label: {
                    figmaSettingsButton(
                        title: "PASTE IP",
                        idleIcon: "icon_clipboard_idle",
                        hoverIcon: "icon_clipboard_hover",
                        isHovered: pasteHovered
                    )
                }
                .buttonStyle(.plain)
                .background(pasteHovered ? Color(red: 0x7E / 255.0, green: 0x7B / 255.0, blue: 0x7B / 255.0) : Color.clear)
                .onHover { pasteHovered = $0 }
            }
        }
        .padding(16)
    }

    private func applyManualIP(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in
            if let octet = Int(part) {
                return (0 ... 255).contains(octet)
            }
            return false
        }) else {
            viewModel.errorMessage = "Invalid IP. Use format like 192.168.0.224."
            return
        }
        viewModel.saveManualLANIP(trimmed, for: device)
    }

    private func figmaSettingsButton(
        title: String,
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

    private var powerButton: some View {
        let isOn = device.isOn ?? false
        let canPower = device.capabilities.canPower

        return Button {
            guard canPower else {
                return
            }
            viewModel.setPower(!isOn, for: device)
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0x1F / 255.0, green: 0x1F / 255.0, blue: 0x1F / 255.0),
                            Color(red: 0x2C / 255.0, green: 0x2A / 255.0, blue: 0x2A / 255.0)
                        ],
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
                .shadow(
                    color: isOn
                        ? Color(red: 0.96, green: 0.71, blue: 0.09).opacity(0.25)
                        : .clear,
                    radius: 30,
                    x: 0,
                    y: 0
                )
                .frame(width: 43.498, height: 43.498)
        }
        .buttonStyle(.plain)
        .disabled(!canPower)
        .opacity(canPower ? 1 : 0.45)
    }

    private var transportBadge: some View {
        let (bg, fg, label): (Color, Color, String) = {
            if let isOnline = device.isOnline, !isOnline {
                return (
                    Color(red: 0x3A / 255.0, green: 0x39 / 255.0, blue: 0x39 / 255.0),
                    Color(red: 0x8F / 255.0, green: 0x8F / 255.0, blue: 0x8F / 255.0),
                    "OFFLINE"
                )
            }

            switch device.transportProfile {
            case .hybrid:
                return (
                    Color(red: 0xF4 / 255.0, green: 0xB5 / 255.0, blue: 0x17 / 255.0),
                    Color(red: 0x62 / 255.0, green: 0x46 / 255.0, blue: 0x00 / 255.0),
                    "HYBRID"
                )
            case .cloud:
                return (
                    Color(red: 0x22 / 255.0, green: 0x65 / 255.0, blue: 0xD4 / 255.0),
                    Color(red: 0xE1 / 255.0, green: 0xEC / 255.0, blue: 0xFF / 255.0),
                    "CLOUD"
                )
            case .lan:
                return (
                    Color(red: 0xB0 / 255.0, green: 0xD4 / 255.0, blue: 0x22 / 255.0),
                    Color(red: 0x44 / 255.0, green: 0x55 / 255.0, blue: 0x00 / 255.0),
                    "LAN"
                )
            }
        }()

        return Text(label)
            .font(.figmaMonoRegular(size: 10))
            .tracking(0.6)
            .foregroundStyle(fg)
            .padding(4)
            .background(bg)
    }

    private var brightnessRow: some View {
        let current = brightnessDraft ?? Double(device.brightness ?? 0)
        let hasKnownBrightness = brightnessDraft != nil || device.brightness != nil

        return VStack(alignment: .leading, spacing: 4) {
            Text(hasKnownBrightness ? "\(Int(current.rounded()))%" : "--")
                .font(.figmaMonoMedium(size: 10))
                .tracking(0.3)
                .foregroundStyle(Color(red: 0x8F / 255.0, green: 0x8F / 255.0, blue: 0x8F / 255.0))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 6) {
                figmaIcon("icon_brightness_min", width: 12, height: 12)

                GridBrightnessTrack(value: current) { draft in
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
}

private struct DeviceCardSkeletonView: View {
    @State private var shimmerPhase: CGFloat = -1.2

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Color(red: 0x27 / 255.0, green: 0x25 / 255.0, blue: 0x25 / 255.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                )

            HStack(alignment: .top, spacing: 24) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 43.498, height: 43.498)
                    .padding(.top, 37.75)

                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 54, height: 16)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 184, height: 11)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 88, height: 8)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 24, height: 8)
                            .frame(maxWidth: .infinity, alignment: .center)

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 184, height: 4)
                    }
                }
                .frame(width: 184, height: 119, alignment: .topLeading)
            }
            .padding(16)
        }
        .frame(width: 299.498, height: 167)
        .overlay(shimmerOverlay.mask(RoundedRectangle(cornerRadius: 40, style: .continuous)))
        .onAppear {
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.2
            }
        }
    }

    private var shimmerOverlay: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = shimmerPhase * width
            LinearGradient(
                colors: [Color.clear, Color.white.opacity(0.14), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width * 0.38, height: proxy.size.height)
            .rotationEffect(.degrees(12))
            .offset(x: x)
        }
    }
}

private struct GridBrightnessTrack: View {
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
