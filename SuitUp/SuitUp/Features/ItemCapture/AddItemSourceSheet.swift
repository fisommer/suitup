import SwiftUI
import PhotosUI
import UIKit

struct AddItemSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var libraryPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPasteURL = false
    @State private var isAnalyzing = false
    @State private var analyzingProgress: (current: Int, total: Int)?
    @State private var errorMessage: String?
    @State private var draftQueue: [QueuedDraft] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.suCanvas.ignoresSafeArea()
                VStack(spacing: SUSpace.md) {
                    HStack {
                        Text("Add to closet")
                            .suSectionTitle()
                            .foregroundStyle(Color.suInkPrimary)
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .font(.custom("Inter Variable", size: 14).weight(.medium))
                            .foregroundStyle(Color.suInkSecondary)
                    }
                    .padding(.horizontal, SUSpace.lg)
                    .padding(.top, SUSpace.md)

                    VStack(spacing: SUSpace.sm) {
                        sourceRow(icon: "camera", title: "Take photo") { showCamera = true }
                        PhotosPicker(
                            selection: $libraryPickerItems,
                            maxSelectionCount: 10,
                            selectionBehavior: .ordered,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            sourceRowLabel(icon: "photo.on.rectangle", title: "Pick from library")
                        }
                        sourceRow(icon: "link", title: "Paste link") { showPasteURL = true }
                    }
                    .padding(.horizontal, SUSpace.lg)

                    Text("Pick one or many photos. Each will be auto-tagged and you'll confirm them one by one.")
                        .suCaption()
                        .foregroundStyle(Color.suInkTertiary)
                        .padding(.horizontal, SUSpace.lg)
                        .padding(.top, SUSpace.xs)

                    if !KeychainStore.hasKey {
                        SUBanner("Add an Anthropic API key in Settings to enable auto-tagging.", style: .warning)
                            .padding(.horizontal, SUSpace.lg)
                            .padding(.top, SUSpace.sm)
                    }

                    Spacer()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await processBatch(images: [image]) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showPasteURL, onDismiss: {
                if AppEvents.shared.lastSavedItemId != nil {
                    dismiss()
                }
            }) {
                PasteURLView()
            }
            .onChange(of: libraryPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    let images = await loadImages(from: newItems)
                    await MainActor.run { libraryPickerItems = [] }
                    if !images.isEmpty {
                        await processBatch(images: images)
                    }
                }
            }
            .overlay {
                if isAnalyzing {
                    AnalyzingOverlay(progress: analyzingProgress)
                }
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
            .sheet(item: Binding<QueuedDraft?>(
                get: { draftQueue.first },
                set: { _ in
                    if !draftQueue.isEmpty { draftQueue.removeFirst() }
                }
            )) { holder in
                ItemConfirmView(draft: holder.draft) { _ in
                    // After save (or discard), the queue auto-advances via the binding above.
                    // If this was the last item, close the source sheet too.
                    if draftQueue.count <= 1 {
                        dismiss()
                    }
                }
            }
        }
    }

    private func sourceRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sourceRowLabel(icon: icon, title: title)
        }
        .buttonStyle(.plain)
    }

    private func sourceRowLabel(icon: String, title: String) -> some View {
        HStack(spacing: SUSpace.md) {
            ZStack {
                Circle()
                    .fill(Color.suAccentSurface)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color.suAccentDeep)
            }
            Text(title)
                .suHeadline()
                .foregroundStyle(Color.suInkPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(Color.suInkTertiary)
        }
        .padding(SUSpace.md)
        .background(Color.suSurface)
        .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                .strokeBorder(Color.suBorder, lineWidth: 1)
        )
    }

    /// Load `UIImage`s from picker items. Preserves selection order.
    private func loadImages(from items: [PhotosPickerItem]) async -> [UIImage] {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                loaded.append(img)
            }
        }
        return loaded
    }

    /// Process N images in parallel (capped at 5 concurrent),
    /// then enqueue all resulting drafts for confirmation.
    @MainActor
    private func processBatch(images: [UIImage]) async {
        guard !images.isEmpty else { return }
        isAnalyzing = true
        analyzingProgress = (current: 0, total: images.count)

        var completed = 0
        let drafts: [ItemConfirmDraft] = await withTaskGroup(of: (Int, ItemConfirmDraft?).self) { group in
            // Cap concurrency at 5
            let concurrency = min(5, images.count)
            var iterator = images.enumerated().makeIterator()
            var inflight = 0

            // Seed
            for _ in 0..<concurrency {
                guard let (idx, image) = iterator.next() else { break }
                inflight += 1
                group.addTask {
                    let draft = await Self.processOne(image: image)
                    return (idx, draft)
                }
            }

            var results: [(Int, ItemConfirmDraft?)] = []
            while inflight > 0 {
                if let pair = await group.next() {
                    results.append(pair)
                    inflight -= 1
                    completed += 1
                    let snapshot = completed
                    await MainActor.run { analyzingProgress = (current: snapshot, total: images.count) }
                    if let (idx, image) = iterator.next() {
                        inflight += 1
                        group.addTask {
                            let draft = await Self.processOne(image: image)
                            return (idx, draft)
                        }
                    }
                }
            }
            return results.sorted(by: { $0.0 < $1.0 }).compactMap { $0.1 }
        }

        isAnalyzing = false
        analyzingProgress = nil

        // If everything failed, surface a single error.
        if drafts.isEmpty {
            errorMessage = "Couldn't process any of the selected photos."
            return
        }

        draftQueue = drafts.map { QueuedDraft(draft: $0) }
    }

    /// Run bg-removal + auto-tag for a single image. Returns nil only if catastrophic
    /// (e.g. image data corrupt). API failures still return a draft with empty tags
    /// so the user can fill them manually.
    private static func processOne(image: UIImage) async -> ItemConfirmDraft? {
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
                print("[AutoTagger] Failed for one item: \(error)")
                // Keep draft, let user fill manually
            }
        }
        return draft
    }
}

struct QueuedDraft: Identifiable {
    let id = UUID()
    let draft: ItemConfirmDraft
}

private struct AnalyzingOverlay: View {
    let progress: (current: Int, total: Int)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                if let progress, progress.total > 1 {
                    Text("Analyzing… \(progress.current) of \(progress.total)")
                        .foregroundStyle(.white)
                } else {
                    Text("Analyzing…")
                        .foregroundStyle(.white)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
