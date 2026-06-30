import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddReferenceSheet: View {
    /// Optional image preloaded from the share extension. When set, the picker step is skipped.
    var preloadedImage: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var libItems: [PhotosPickerItem] = []
    @State private var preview: UIImage?
    @State private var note: String = ""
    @State private var isSaving: Bool = false
    @State private var isLoadingBatch: Bool = false
    @State private var batchProgress: (current: Int, total: Int)?
    @State private var presentationDetent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            ZStack {
                Color.suCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SUSpace.lg) {
                        HStack {
                            Text("Add reference")
                                .suSectionTitle()
                                .foregroundStyle(Color.suInkPrimary)
                            Spacer()
                            Button("Cancel") { dismiss() }
                                .font(.custom("Inter Variable", size: 14).weight(.medium))
                                .foregroundStyle(Color.suInkSecondary)
                        }
                        .padding(.horizontal, SUSpace.lg)
                        .padding(.top, SUSpace.lg)

                        if let preview {
                            // Single-image confirm view
                            Image(uiImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 360)
                                .frame(maxWidth: .infinity)
                                .background(Color.suSurfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: SURadius.lg, style: .continuous))
                                .padding(.horizontal, SUSpace.lg)

                            VStack(alignment: .leading, spacing: SUSpace.sm) {
                                Text("Note")
                                    .suLabel()
                                    .foregroundStyle(Color.suInkTertiary)
                                TextField("Optional (e.g. \"love the layering\")", text: $note, axis: .vertical)
                                    .suBody()
                                    .foregroundStyle(Color.suInkPrimary)
                                    .lineLimit(1...3)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color.suSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous)
                                            .strokeBorder(Color.suBorder, lineWidth: 1)
                                    )
                            }
                            .padding(.horizontal, SUSpace.lg)

                            SUButton(
                                isSaving ? "Saving…" : "Add to references",
                                isLoading: isSaving
                            ) { save(image: preview) }
                                .padding(.horizontal, SUSpace.lg)
                        } else {
                            // Multi-pick picker
                            VStack(spacing: SUSpace.md) {
                                PhotosPicker(
                                    selection: $libItems,
                                    maxSelectionCount: 20,
                                    selectionBehavior: .ordered,
                                    matching: .images,
                                    photoLibrary: .shared()
                                ) {
                                    HStack(spacing: SUSpace.md) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.suAccentSurface)
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "photo.on.rectangle")
                                                .font(.system(size: 16, weight: .light))
                                                .foregroundStyle(Color.suAccentDeep)
                                        }
                                        Text("Pick from library")
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
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, SUSpace.lg)

                            Text("References are outfit photos you find inspiring — from Pinterest, Instagram, fashion editorials. SuitUp uses them as your taste anchor.")
                                .suCaption()
                                .foregroundStyle(Color.suInkTertiary)
                                .padding(.horizontal, SUSpace.lg)
                        }

                        Spacer().frame(height: SUSpace.lg)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .presentationDetents([.medium, .large], selection: $presentationDetent)
            .presentationDragIndicator(.visible)
            .overlay {
                if isLoadingBatch {
                    BatchSavingOverlay(progress: batchProgress)
                }
            }
            .onChange(of: libItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    if newItems.count == 1 {
                        // Single pick → load + show single-image confirm
                        if let data = try? await newItems[0].loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            await MainActor.run {
                                preview = img
                                libItems = []
                                // Expand to full height so the user can see the preview + note + save button.
                                withAnimation(SUMotion.standard) { presentationDetent = .large }
                            }
                        }
                    } else {
                        // Multi-pick → save all directly, no per-item confirm
                        await saveBatch(items: newItems)
                    }
                }
            }
            .onAppear {
                if preview == nil, let preloadedImage {
                    preview = preloadedImage
                    presentationDetent = .large
                }
            }
        }
    }

    private func save(image: UIImage) {
        isSaving = true
        let id = UUID()
        do {
            let imagePath = try ImageStore.save(image, folder: .references, name: "\(id)", maxDimension: 1024)
            let thumbPath = try ImageStore.save(image, folder: .references, name: "\(id)-thumb", maxDimension: 256)
            let ref = ReferenceLook(
                id: id,
                imagePath: imagePath,
                thumbnailPath: thumbPath,
                source: .library,
                note: note.isEmpty ? nil : note
            )
            modelContext.insert(ref)
            try? modelContext.save()
            AppEvents.shared.didSaveItem(id: id, name: "reference")
            dismiss()
        } catch {
            print("[AddReference] Save failed: \(error)")
            isSaving = false
        }
    }

    @MainActor
    private func saveBatch(items: [PhotosPickerItem]) async {
        isLoadingBatch = true
        batchProgress = (current: 0, total: items.count)

        var savedCount = 0
        for (idx, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                let id = UUID()
                if let imagePath = try? ImageStore.save(img, folder: .references, name: "\(id)", maxDimension: 1024),
                   let thumbPath = try? ImageStore.save(img, folder: .references, name: "\(id)-thumb", maxDimension: 256) {
                    let ref = ReferenceLook(
                        id: id,
                        imagePath: imagePath,
                        thumbnailPath: thumbPath,
                        source: .library
                    )
                    modelContext.insert(ref)
                    savedCount += 1
                }
            }
            batchProgress = (current: idx + 1, total: items.count)
        }
        try? modelContext.save()
        isLoadingBatch = false
        batchProgress = nil
        libItems = []
        if savedCount > 0 {
            AppEvents.shared.didSaveItem(id: UUID(), name: "\(savedCount) reference\(savedCount == 1 ? "" : "s")")
        }
        dismiss()
    }
}

private struct BatchSavingOverlay: View {
    let progress: (current: Int, total: Int)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: SUSpace.md) {
                ProgressView().tint(.white)
                if let progress {
                    Text("Saving \(progress.current) of \(progress.total)")
                        .suCaption()
                        .foregroundStyle(.white)
                } else {
                    Text("Saving…")
                        .suCaption()
                        .foregroundStyle(.white)
                }
            }
            .padding(SUSpace.lg)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SURadius.md))
        }
    }
}
