import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var keyDraft = ""
    @State private var keyExists = false
    @State private var showSavedToast = false

    // Data section state
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var showClearConfirm = false
    @State private var clearError: String?
    @State private var dataError: String?

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

                Section {
                    Button {
                        runExport()
                    } label: {
                        HStack {
                            Label("Export all data", systemImage: "square.and.arrow.up")
                            Spacer()
                            if isExporting {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isExporting)

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear all data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export is a JSON snapshot — image paths included, image files are not. Clearing removes every item, outfit, reference, and image file. Your API key is preserved.")
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
            .alert("Clear all data?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear everything", role: .destructive) { runClear() }
            } message: {
                Text("This permanently deletes every item, outfit, reference, recreate attempt, and image file. The API key in Keychain is kept. There is no undo.")
            }
            .alert("Error", isPresented: Binding(
                get: { dataError != nil },
                set: { if !$0 { dataError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dataError ?? "")
            }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                // Clean up the temp export file once the share sheet closes.
                if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
                exportURL = nil
            }) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
        }
    }

    // MARK: - Data actions

    private func runExport() {
        isExporting = true
        Task {
            do {
                let url = try await MainActor.run {
                    try DataPortability.exportAll(context: modelContext)
                }
                await MainActor.run {
                    exportURL = url
                    isExporting = false
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    dataError = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func runClear() {
        do {
            try DataPortability.clearAll(context: modelContext)
        } catch {
            dataError = "Clear failed: \(error.localizedDescription)"
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
