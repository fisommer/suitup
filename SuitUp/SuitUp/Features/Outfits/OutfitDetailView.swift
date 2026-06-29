import SwiftUI
import SwiftData

struct OutfitDetailView: View {
    @Bindable var outfit: Outfit
    @Query private var allItems: [Item]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false
    @State private var loggedWearAt: Date?

    private var items: [Item] {
        let lookup = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        return outfit.itemIds.compactMap { lookup[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StoredImage(relativePath: outfit.coverImagePath, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 500)
                    .background(Color(.secondarySystemBackground))

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $outfit.name)
                        .font(.title2.bold())
                        .onChange(of: outfit.name) { _, _ in try? modelContext.save() }
                    if let rationale = outfit.rationale, !rationale.isEmpty {
                        Text(rationale)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)

                Button {
                    let event = WearEvent(outfitId: outfit.id)
                    modelContext.insert(event)
                    try? modelContext.save()
                    loggedWearAt = Date()
                } label: {
                    Label(loggedWearAt == nil ? "Wore today" : "Logged ✓", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .disabled(loggedWearAt != nil)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Items")
                        .font(.headline)
                        .padding(.horizontal)
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            HStack(spacing: 12) {
                                StoredImage(relativePath: item.thumbnailPath, contentMode: .fit)
                                    .frame(width: 60, height: 75)
                                    .background(Color(.tertiarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text(item.subcategory.isEmpty ? item.category.displayName : item.subcategory)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete outfit", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .confirmationDialog(
            "Delete this outfit?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                ImageStore.delete(outfit.coverImagePath)
                modelContext.delete(outfit)
                try? modelContext.save()
                dismiss()
            }
        }
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
        }
    }
}
