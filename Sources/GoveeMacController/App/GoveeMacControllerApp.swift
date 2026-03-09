import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct GoveeMacControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    private static let menuBarIconPointSize: CGFloat = 16

    init() {
        FigmaResources.registerFontsIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            RootView(viewModel: viewModel)
                .frame(width: 648, height: 470)
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        if let image = menuBarTemplateImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .accessibilityLabel("Govee")
        } else {
            Image(systemName: "lightbulb.max.fill")
                .accessibilityLabel("Govee")
        }
    }

    private var menuBarTemplateImage: NSImage? {
        guard let source = FigmaResources.image(named: "power_off") else {
            return nil
        }

        let targetSize = NSSize(width: Self.menuBarIconPointSize, height: Self.menuBarIconPointSize)
        let template = NSImage(size: targetSize)

        template.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        template.unlockFocus()

        template.isTemplate = true
        return template
    }
}
