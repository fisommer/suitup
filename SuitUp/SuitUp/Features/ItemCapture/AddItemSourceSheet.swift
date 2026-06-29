import SwiftUI
import PhotosUI
import UIKit
import Combine

@MainActor
final class AddItemFlowState: ObservableObject {
    @Published var libraryPickerItem: PhotosPickerItem?
    @Published var showCamera = false
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var pendingDraft: ItemConfirmDraft?
    @Published var showPasteURL = false   // wired up in Phase 4
}

struct AddItemSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = AddItemFlowState()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        state.showCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera")
                    }
                    PhotosPicker(selection: $state.libraryPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Pick from library", systemImage: "photo")
                    }
                    Button {
                        state.showPasteURL = true
                    } label: {
                        Label("Paste link", systemImage: "link")
                    }
                    .disabled(true) // Phase 4
                }
                if !KeychainStore.hasKey {
                    Section {
                        Label("Add an Anthropic API key in Settings to enable auto-tagging.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Add to closet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $state.showCamera) {
                CameraPicker { image in
                    Task { await process(image: image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: state.libraryPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await process(image: img)
                    }
                }
            }
            .overlay {
                if state.isAnalyzing { AnalyzingOverlay() }
            }
            .alert(
                "Tagging failed",
                isPresented: Binding(
                    get: { state.errorMessage != nil },
                    set: { if !$0 { state.errorMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(state.errorMessage ?? "") }
            )
            .sheet(item: Binding<DraftHolder?>(
                get: { state.pendingDraft.map { DraftHolder(draft: $0) } },
                set: { state.pendingDraft = $0?.draft }
            )) { holder in
                ItemConfirmView(draft: holder.draft)
            }
        }
    }

    @MainActor
    private func process(image: UIImage) async {
        state.isAnalyzing = true
        defer { state.isAnalyzing = false }

        let bgRemoved = await BackgroundRemoval.removeBackground(from: image)
        var draft = ItemConfirmDraft(originalImage: image, bgRemovedImage: bgRemoved)

        if KeychainStore.hasKey {
            do {
                let result = try await AutoTagger().tag(image: bgRemoved)
                if result.isNotClothing {
                    state.errorMessage = "This doesn't look like a clothing item. You can still add it manually."
                }
                draft.name = result.name
                draft.category = result.category
                draft.subcategory = result.subcategory
                draft.colors = result.colors
                draft.formality = result.formality
                draft.seasons = Set(result.seasons)
                draft.pattern = result.pattern ?? ""
                draft.material = result.material ?? ""
                draft.fit = result.fit
                draft.occasionTags = result.occasionTags
                draft.materialIsGuess = true
            } catch {
                state.errorMessage = error.localizedDescription
            }
        }

        state.pendingDraft = draft
    }
}

private struct DraftHolder: Identifiable {
    let id = UUID()
    let draft: ItemConfirmDraft
}

private struct AnalyzingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Analyzing…")
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
