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
            ZStack {
                Color.suCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SUSpace.xl) {
                        HStack {
                            Text("Settings")
                                .suTitle()
                                .foregroundStyle(Color.suInkPrimary)
                            Spacer()
                            Button("Done") { dismiss() }
                                .font(.custom("Inter Variable", size: 14).weight(.medium))
                                .foregroundStyle(Color.suInkSecondary)
                        }
                        .padding(.horizontal, SUSpace.lg)
                        .padding(.top, SUSpace.md)

                        // API key section
                        VStack(alignment: .leading, spacing: SUSpace.md) {
                            SUSectionHeader(title: "Anthropic API key")
                                .padding(.horizontal, SUSpace.lg)

                            VStack(alignment: .leading, spacing: SUSpace.md) {
                                if keyExists {
                                    SUBanner("Key stored in Keychain", style: .success)
                                    HStack(spacing: SUSpace.sm) {
                                        SUButton("Replace key", style: .secondary, fullWidth: true) {
                                            keyDraft = ""
                                            // Force re-entry by clearing existence; user will save new key
                                            KeychainStore.delete()
                                            keyExists = false
                                        }
                                        SUButton("Delete", style: .destructive, fullWidth: true) {
                                            KeychainStore.delete()
                                            keyExists = false
                                        }
                                    }
                                } else {
                                    SUTextField(
                                        label: "API Key",
                                        text: $keyDraft,
                                        placeholder: "sk-ant-...",
                                        isSecure: true,
                                        autocapitalization: .never,
                                        autocorrect: false
                                    )
                                    SUButton("Save key") {
                                        guard !keyDraft.isEmpty else { return }
                                        KeychainStore.set(keyDraft)
                                        keyDraft = ""
                                        keyExists = true
                                        showSavedToast = true
                                    }
                                }
                                Text("Used for auto-tagging, styling, and recreating outfits. Get one at console.anthropic.com.")
                                    .suCaption()
                                    .foregroundStyle(Color.suInkTertiary)
                            }
                            .padding(.horizontal, SUSpace.lg)
                        }

                        // Data section
                        VStack(alignment: .leading, spacing: SUSpace.md) {
                            SUSectionHeader(title: "Data")
                                .padding(.horizontal, SUSpace.lg)

                            VStack(spacing: SUSpace.sm) {
                                SUButton(
                                    isExporting ? "Exporting…" : "Export all data",
                                    style: .secondary,
                                    icon: "square.and.arrow.up",
                                    isLoading: isExporting
                                ) { runExport() }

                                SUButton("Clear all data", style: .destructive, icon: "trash") {
                                    showClearConfirm = true
                                }
                            }
                            .padding(.horizontal, SUSpace.lg)

                            Text("Export is a JSON snapshot — image paths included, image files are not. Clearing removes every item, outfit, reference, and image file. Your API key is preserved.")
                                .suCaption()
                                .foregroundStyle(Color.suInkTertiary)
                                .padding(.horizontal, SUSpace.lg)
                        }

                        // About section
                        VStack(alignment: .leading, spacing: SUSpace.md) {
                            SUSectionHeader(title: "About")
                                .padding(.horizontal, SUSpace.lg)

                            VStack(spacing: 0) {
                                aboutRow(label: "Version", value: Bundle.main.shortVersion)
                                Divider().background(Color.suBorder)
                                aboutRow(label: "Build", value: Bundle.main.buildNumber)
                            }
                            .background(Color.suSurface)
                            .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                                    .strokeBorder(Color.suBorder, lineWidth: 1)
                            )
                            .padding(.horizontal, SUSpace.lg)
                        }

                        Color.clear.frame(height: 40)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
                if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
                exportURL = nil
            }) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .suBody()
                .foregroundStyle(Color.suInkPrimary)
            Spacer()
            Text(value)
                .suBody()
                .foregroundStyle(Color.suInkTertiary)
        }
        .padding(.horizontal, SUSpace.md)
        .padding(.vertical, 14)
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
