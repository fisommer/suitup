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

    private var canSave: Bool {
        selectedIds.count >= 2 && selectedIds.count <= 6 && !name.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.suCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SUSpace.lg) {
                        HStack {
                            Text("New outfit")
                                .suSectionTitle()
                                .foregroundStyle(Color.suInkPrimary)
                            Spacer()
                            Button("Cancel") { dismiss() }
                                .font(.custom("Inter Variable", size: 14).weight(.medium))
                                .foregroundStyle(Color.suInkSecondary)
                        }
                        .padding(.horizontal, SUSpace.lg)
                        .padding(.top, SUSpace.lg)

                        VStack(alignment: .leading, spacing: SUSpace.md) {
                            SUTextField(label: "Name", text: $name, placeholder: "Linen Saturday")
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Notes (optional)")
                                    .suLabel()
                                    .foregroundStyle(Color.suInkTertiary)
                                TextField("e.g. weekend lunch fit", text: $rationale, axis: .vertical)
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
                        }
                        .padding(.horizontal, SUSpace.lg)

                        if !selectedItems.isEmpty {
                            VStack(alignment: .leading, spacing: SUSpace.md) {
                                SUSectionHeader(title: "Preview")
                                    .padding(.horizontal, SUSpace.lg)
                                CollageThumb(items: selectedItems)
                                    .frame(height: 240)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.suSurfaceMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
                                    .padding(.horizontal, SUSpace.lg)
                            }
                        }

                        VStack(alignment: .leading, spacing: SUSpace.md) {
                            SUSectionHeader(
                                title: "Pick 2–6 items",
                                count: selectedIds.isEmpty ? nil : selectedIds.count
                            )
                            .padding(.horizontal, SUSpace.lg)

                            if allItems.isEmpty {
                                Text("Add items to your closet first.")
                                    .suBody()
                                    .foregroundStyle(Color.suInkTertiary)
                                    .padding(.horizontal, SUSpace.lg)
                            } else {
                                VStack(spacing: SUSpace.sm) {
                                    ForEach(allItems) { item in
                                        Button { toggle(item.id) } label: {
                                            pickerRow(item: item, isSelected: selectedIds.contains(item.id))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, SUSpace.lg)
                            }
                        }

                        SUButton("Save outfit", style: canSave ? .primary : .disabled) {
                            save()
                        }
                        .padding(.horizontal, SUSpace.lg)
                        .padding(.top, SUSpace.sm)

                        Spacer().frame(height: SUSpace.lg)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func pickerRow(item: Item, isSelected: Bool) -> some View {
        HStack(spacing: SUSpace.md) {
            StoredImage(relativePath: item.thumbnailPath, contentMode: .fill)
                .frame(width: 48, height: 60)
                .background(Color.suSurfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.custom("Inter Variable", size: 14).weight(.medium))
                    .foregroundStyle(Color.suInkPrimary)
                    .lineLimit(1)
                Text(item.category.displayName)
                    .suCaption()
                    .foregroundStyle(Color.suInkTertiary)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(isSelected ? Color.suAccentDeep : Color.suInkTertiary)
        }
        .padding(SUSpace.md)
        .background(isSelected ? Color.suAccentSurface : Color.suSurface)
        .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                .strokeBorder(isSelected ? Color.suAccent : Color.suBorder, lineWidth: isSelected ? 1.5 : 1)
        )
    }

    private func toggle(_ id: UUID) {
        if selectedIds.contains(id) { selectedIds.remove(id) }
        else { selectedIds.insert(id) }
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
