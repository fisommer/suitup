import SwiftUI
import SwiftData

struct OutfitBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @State private var selectedIds: Set<UUID> = []
    @State private var name: String = "New outfit"
    @State private var rationale: String = ""

    private var selectedItems: [Item] {
        let lookup = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        return Array(selectedIds).compactMap { lookup[$0] }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Notes (optional)", text: $rationale, axis: .vertical)
                        .lineLimit(1...3)
                }

                if !selectedItems.isEmpty {
                    Section("Preview") {
                        CollageThumb(items: selectedItems)
                            .frame(height: 240)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Section {
                    if allItems.isEmpty {
                        Text("Add items to your closet first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allItems) { item in
                            Button {
                                toggle(item.id)
                            } label: {
                                HStack(spacing: 12) {
                                    StoredImage(relativePath: item.thumbnailPath, contentMode: .fit)
                                        .frame(width: 44, height: 56)
                                        .background(Color(.tertiarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                        Text(item.category.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedIds.contains(item.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Pick 2–6 items")
                } footer: {
                    if selectedIds.count < 2 {
                        Text("Pick at least 2 items.")
                    } else if selectedIds.count > 6 {
                        Text("Maximum 6 items.")
                    } else {
                        Text("\(selectedIds.count) selected")
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Save outfit")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(selectedIds.count < 2 || selectedIds.count > 6 || name.isEmpty)
                }
            }
            .navigationTitle("New outfit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    @MainActor
    private func save() {
        let items = selectedItems
        let collage = CollageRenderer.render(items: items)
        let id = UUID()
        do {
            let coverPath = try ImageStore.save(collage, folder: .outfits, name: "\(id)", maxDimension: 1024)
            let outfit = Outfit(
                id: id,
                name: name,
                itemIds: items.map(\.id),
                coverImagePath: coverPath,
                source: .manuallyBuilt,
                rationale: rationale.isEmpty ? nil : rationale
            )
            modelContext.insert(outfit)
            try? modelContext.save()
            dismiss()
        } catch {
            print("[OutfitBuilder] Save failed: \(error)")
        }
    }
}
