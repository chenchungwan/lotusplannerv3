import SwiftUI

#Preview {
    IntegrationsView()
}

struct IntegrationsView: View {
    @ObservedObject private var navigationManager = NavigationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var anthropicAPIKeyInput = ""
    @State private var anthropicAPIKeyPreview: String?
    @State private var anthropicAPIKeyMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("AI") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField(
                            anthropicAPIKeyPreview == nil ? "Anthropic API key" : "Replace \(anthropicAPIKeyPreview!)",
                            text: $anthropicAPIKeyInput
                        )
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                        if let anthropicAPIKeyMessage {
                            Text(anthropicAPIKeyMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Button {
                            saveAnthropicAPIKey()
                        } label: {
                            Label("Save Key", systemImage: "key.fill")
                        }
                        .disabled(anthropicAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()

                        Button(role: .destructive) {
                            clearAnthropicAPIKey()
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .disabled(anthropicAPIKeyPreview == nil)
                    }
                }
            }
            .navigationTitle("Integrations")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                refreshAnthropicAPIKeyStatus()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        navigationManager.showingIntegrations = false
                        dismiss()
                    }
                }
            }
        }
    }

    private func refreshAnthropicAPIKeyStatus() {
        anthropicAPIKeyPreview = ClaudeAIService.shared.apiKeyPreview()
        anthropicAPIKeyMessage = anthropicAPIKeyPreview == nil
            ? "Used by AI Task Entry. Stored securely in Keychain."
            : "Anthropic key saved securely in Keychain."
    }

    private func saveAnthropicAPIKey() {
        do {
            try ClaudeAIService.shared.saveAPIKey(anthropicAPIKeyInput)
            anthropicAPIKeyInput = ""
            refreshAnthropicAPIKeyStatus()
        } catch {
            anthropicAPIKeyMessage = error.localizedDescription
        }
    }

    private func clearAnthropicAPIKey() {
        do {
            try ClaudeAIService.shared.saveAPIKey("")
            anthropicAPIKeyInput = ""
            refreshAnthropicAPIKeyStatus()
        } catch {
            anthropicAPIKeyMessage = error.localizedDescription
        }
    }
}
