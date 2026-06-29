import SwiftUI
import PhotosUI
import UIKit

struct AddItemSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var libraryPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var draftToConfirm: IdentifiedDraft?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera")
                    }
                    PhotosPicker(selection: $libraryPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Pick from library", systemImage: "photo")
                    }
                    Button {} label: {
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
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await process(image: image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: libraryPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await process(image: img)
                    }
                    // Reset picker so the same selection doesn't refire.
                    await MainActor.run { libraryPickerItem = nil }
                }
            }
            .overlay {
                if isAnalyzing { AnalyzingOverlay() }
            }
            .alert(
                "Tagging failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(errorMessage ?? "") }
            )
            .sheet(item: $draftToConfirm) { holder in
                ItemConfirmView(draft: holder.draft) { _ in
                    // After a successful save, close the parent add-source sheet
                    // so the user lands back on the closet with their new item.
                    dismiss()
                }
            }
        }
    }

    @MainActor
    private func process(image: UIImage) async {
        isAnalyzing = true
        let outcome = await BackgroundRemoval.attemptRemoval(from: image)
        let bgRemoved: UIImage
        let bgSucceeded: Bool
        switch outcome {
        case .removed(let img):
            bgRemoved = img
            bgSucceeded = true
        case .noSubjectFound(let img), .failed(_, let img):
            bgRemoved = img
            bgSucceeded = false
        }
        var draft = ItemConfirmDraft(
            originalImage: image,
            bgRemovedImage: bgRemoved,
            useBackgroundRemoved: bgSucceeded
        )
        draft.bgRemovalSucceeded = bgSucceeded
        var fatalError: String? = nil

        if KeychainStore.hasKey {
            do {
                let result = try await AutoTagger().tag(image: bgRemoved)
                if result.isNotClothing {
                    print("[AutoTagger] Item identified as not-clothing")
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
                print("[AutoTagger] Failed: \(error)")
                fatalError = error.localizedDescription
            }
        } else {
            print("[AutoTagger] No API key — skipping auto-tag, opening manual confirm")
        }

        isAnalyzing = false

        if let fatalError {
            errorMessage = fatalError
            return
        }
        draftToConfirm = IdentifiedDraft(draft: draft)
    }
}

private struct IdentifiedDraft: Identifiable {
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
