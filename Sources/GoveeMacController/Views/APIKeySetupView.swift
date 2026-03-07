import SwiftUI

struct APIKeySetupView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Govee API Setup")
                .font(.title2)
                .bold()

            Text("Paste your Govee developer API key from the Govee Home app. It will be stored in macOS Keychain.")
                .foregroundStyle(.secondary)

            SecureField("Govee API key", text: $viewModel.apiKeyInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save API Key") {
                    viewModel.saveAPIKey()
                }
                .keyboardShortcut(.defaultAction)

                Button("Clear") {
                    viewModel.apiKeyInput = ""
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 320)
    }
}
