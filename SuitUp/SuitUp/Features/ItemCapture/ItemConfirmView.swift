import SwiftUI
import SwiftData

struct ItemConfirmView: View {
    @State var draft: ItemConfirmDraft
    var onSaved: ((UUID) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var colorsText: String = ""
    @State private var occasionTagsText: String = ""

    init(draft: ItemConfirmDraft, onSaved: ((UUID) -> Void)? = nil) {
        _draft = State(initialValue: draft)
        _colorsText = State(initialValue: draft.colors.joined(separator: ", "))
        _occasionTagsText = State(initialValue: draft.occasionTags.joined(separator: ", "))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
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
                    Button("Save to closet") { save() }
                        .frame(maxWidth: .infinity)
                    Button("Discard", role: .destructive) { dismiss() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
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
