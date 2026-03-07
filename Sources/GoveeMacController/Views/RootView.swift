import SwiftUI

struct RootView: View {
    @StateObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.hasAPIKey {
                DeviceListView(viewModel: viewModel)
            } else {
                APIKeySetupView(viewModel: viewModel)
            }
        }
        .task {
            viewModel.bootstrap()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }
}
