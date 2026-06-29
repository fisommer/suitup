import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""
    @State private var keyExists = false
    @State private var showSavedToast = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if keyExists {
                        Label("Key stored in Keychain", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Replace key") { keyDraft = "" }
                        Button("Delete key", role: .destructive) {
                            KeychainStore.delete()
                            keyExists = false
                        }
                    } else {
                        SecureField("sk-ant-...", text: $keyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") {
                            guard !keyDraft.isEmpty else { return }
                            KeychainStore.set(keyDraft)
                            keyDraft = ""
                            keyExists = true
                            showSavedToast = true
                        }
                        .disabled(keyDraft.isEmpty)
                    }
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("Used for auto-tagging, styling, and recreating outfits. Get one at console.anthropic.com.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.shortVersion)
                    LabeledContent("Build", value: Bundle.main.buildNumber)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { keyExists = KeychainStore.hasKey }
            .alert("Saved", isPresented: $showSavedToast) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}

#Preview {
    SettingsView()
}
