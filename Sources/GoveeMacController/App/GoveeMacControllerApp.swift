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

    init() {
        FigmaResources.registerFontsIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            RootView(viewModel: viewModel)
            .frame(width: 648, height: 470)
        } label: {
            Label("Govee", systemImage: "lightbulb.max.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
