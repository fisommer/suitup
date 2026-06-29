import SwiftUI
import SwiftData
import PhotosUI

struct ItemConfirmView: View {
    @State var draft: ItemConfirmDraft
    var onSaved: ((UUID) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var colorsText: String = ""
    @State private var occasionTagsText: String = ""
    @State private var isImproving: Bool = false
    @State private var improveError: String?
    @State private var additionalPickerItem: PhotosPickerItem?

    init(draft: ItemConfirmDraft, onSaved: ((UUID) -> Void)? = nil) {
        _draft = State(initialValue: draft)
        _colorsText = State(initialValue: draft.colors.joined(separator: ", "))
        _occasionTagsText = State(initialValue: draft.occasionTags.joined(separator: ", "))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Form {
                    Section {
                        Image(uiImage: draft.useBackgroundRemoved ? draft.bgRemovedImage : draft.originalImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 280)
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        if draft.bgRemovalSucceeded {
                            Toggle("Background removed", isOn: $draft.useBackgroundRemoved)
                        } else {
                            Label("Background couldn't be removed automatically", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if KeychainStore.hasKey {
                            Button {
                                Task { await improveWithAI() }
                            } label: {
                                HStack {
                                    if isImproving {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(isImproving ? "Improving…" : "Improve with AI")
                                    Spacer()
                                }
                            }
                            .disabled(isImproving)
                        }
                    }

                    Section {
                        additionalPhotosRow
                    } header: {
                        Text("Additional photos")
                    } footer: {
                        Text("Back, prints, detail shots. Up to 2 more — only the primary image is used by AI styling.")
                    }

                Section("Details") {
                    TextField("Name", text: $draft.name)
                    Picker("Category", selection: $draft.category) {
                        ForEach(ItemCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                    TextField("Subcategory (e.g. Shirt)", text: $draft.subcategory)
                    Picker("Formality", selection: $draft.formality) {
                        ForEach(Formality.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    TextField("Colors (comma-separated)", text: $colorsText)
                        .autocorrectionDisabled()
                }

                Section("Seasons") {
                    ForEach(Season.allCases, id: \.self) { season in
                        Toggle(season.rawValue.capitalized, isOn: Binding(
                            get: { draft.seasons.contains(season) },
                            set: { isOn in
                                if isOn { draft.seasons.insert(season) } else { draft.seasons.remove(season) }
                            }
                        ))
                    }
                }

                Section("Optional") {
                    TextField("Brand", text: $draft.brand)
                    TextField("Size", text: $draft.size)
                    HStack {
                        TextField("Material", text: $draft.material)
                        if draft.materialIsGuess && !draft.material.isEmpty {
                            Text("guess")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Pattern", text: $draft.pattern)
                    Picker("Fit", selection: Binding(
                        get: { draft.fit ?? .regular },
                        set: { draft.fit = $0 }
                    )) {
                        ForEach(Fit.allCases, id: \.self) { f in
                            Text(f.rawValue.capitalized).tag(f)
                        }
                    }
                    TextField("Occasion tags (comma-separated)", text: $occasionTagsText)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button("Discard", role: .destructive) { dismiss() }
                        .frame(maxWidth: .infinity)
                }

                // Spacer at the bottom so the last form content isn't covered by the floating Save bar.
                Section {
                    Color.clear.frame(height: 60)
                }
                .listRowBackground(Color.clear)
            }

            floatingSaveBar
        }
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Couldn't improve tags",
                isPresented: Binding(
                    get: { improveError != nil },
                    set: { if !$0 { improveError = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(improveError ?? "") }
            )
            .onChange(of: additionalPickerItem) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            if draft.additionalImages.count < 2 {
                                draft.additionalImages.append(img)
                            }
                            additionalPickerItem = nil
                        }
                    } else {
                        await MainActor.run { additionalPickerItem = nil }
                    }
                }
            }
        }
    }

    private var additionalPhotosRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(draft.additionalImages.enumerated()), id: \.offset) { idx, img in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 88, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button {
                            draft.additionalImages.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .offset(x: 6, y: -6)
                    }
                }
                if draft.additionalImages.count < 2 {
                    PhotosPicker(selection: $additionalPickerItem, matching: .images, photoLibrary: .shared()) {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.title2)
                            Text("Add")
                                .font(.caption2)
                        }
                        .frame(width: 88, height: 110)
                        .foregroundStyle(.tint)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var floatingSaveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                save()
            } label: {
                Text("Save to closet")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    /// Run AutoTagger over the current image and merge results into the draft,
    /// preserving any field the user already filled.
    @MainActor
    private func improveWithAI() async {
        isImproving = true
        defer { isImproving = false }
        let baseImage = draft.useBackgroundRemoved ? draft.bgRemovedImage : draft.originalImage
        do {
            let result = try await AutoTagger().tag(image: baseImage)
            // Only fill empty fields — never overwrite user edits.
            if draft.name.isEmpty { draft.name = result.name }
            // Category: only override if user hasn't manually adjusted past the default.
            // Heuristic: if subcategory is empty, treat category as auto-assignable.
            if draft.subcategory.isEmpty {
                draft.category = result.category
                draft.subcategory = result.subcategory
            }
            if colorsText.isEmpty && !result.colors.isEmpty {
                colorsText = result.colors.joined(separator: ", ")
                draft.colors = result.colors
            }
            // Formality: only override if seasons not yet picked (proxy for "still default").
            if draft.seasons.isEmpty {
                draft.formality = result.formality
                draft.seasons = Set(result.seasons)
            }
            if draft.pattern.isEmpty, let p = result.pattern { draft.pattern = p }
            if draft.material.isEmpty, let m = result.material {
                draft.material = m
                draft.materialIsGuess = true
            }
            if draft.fit == nil { draft.fit = result.fit }
            if occasionTagsText.isEmpty && !result.occasionTags.isEmpty {
                occasionTagsText = result.occasionTags.joined(separator: ", ")
                draft.occasionTags = result.occasionTags
            }
        } catch {
            print("[ImproveWithAI] Failed: \(error)")
            improveError = error.localizedDescription
        }
    }

    private func save() {
        let baseImage = draft.useBackgroundRemoved ? draft.bgRemovedImage : draft.originalImage
        let id = UUID()
        do {
            let imagePath = try ImageStore.save(baseImage, folder: .items, name: "\(id)", maxDimension: 1024)
            let thumb = try ImageStore.save(baseImage, folder: .items, name: "\(id)-thumb", maxDimension: 256)
            let original = try ImageStore.save(draft.originalImage, folder: .items, name: "\(id)-original", maxDimension: 1600)
            let extraPaths: [String] = try draft.additionalImages.enumerated().map { idx, img in
                try ImageStore.save(img, folder: .items, name: "\(id)-extra-\(idx)", maxDimension: 1024)
            }
            let colors = colorsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let occasionTags = occasionTagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let item = Item(
                id: id,
                imagePath: imagePath,
                originalImagePath: original,
                thumbnailPath: thumb,
                additionalImagePaths: extraPaths,
                source: draft.source,
                sourceUrl: draft.sourceUrl,
                name: draft.name.isEmpty ? "Untitled" : draft.name,
                category: draft.category,
                subcategory: draft.subcategory,
                colors: colors,
                formality: draft.formality,
                seasons: Array(draft.seasons),
                pattern: draft.pattern.isEmpty ? nil : draft.pattern,
                material: draft.material.isEmpty ? nil : draft.material,
                brand: draft.brand.isEmpty ? nil : draft.brand,
                size: draft.size.isEmpty ? nil : draft.size,
                fit: draft.fit,
                occasionTags: occasionTags,
                purchaseDate: draft.purchaseDate,
                price: draft.price,
                purchasedFrom: draft.purchasedFrom,
                notes: draft.notes.isEmpty ? nil : draft.notes
            )
            modelContext.insert(item)
            try? modelContext.save()
            AppEvents.shared.didSaveItem(id: id, name: item.name)
            onSaved?(id)
            dismiss()
        } catch {
            print("Save failed: \(error)")
        }
    }
}
