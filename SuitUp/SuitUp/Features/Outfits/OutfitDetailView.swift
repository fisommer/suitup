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
            VStack(alignment: .leading, spacing: SUSpace.lg) {
                StoredImage(relativePath: outfit.coverImagePath, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 500)
                    .background(Color.suSurfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SURadius.lg, style: .continuous))
                    .padding(.horizontal, SUSpace.lg)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $outfit.name)
                        .suTitle()
                        .foregroundStyle(Color.suInkPrimary)
                        .onChange(of: outfit.name) { _, _ in try? modelContext.save() }
                    if let rationale = outfit.rationale, !rationale.isEmpty {
                        Text(rationale)
                            .suCaption()
                            .foregroundStyle(Color.suInkSecondary)
                    }
                }
                .padding(.horizontal, SUSpace.lg)

                SUButton(
                    loggedWearAt == nil ? "Wore today" : "Logged ✓",
                    style: loggedWearAt == nil ? .secondary : .disabled,
                    icon: "checkmark.circle"
                ) {
                    let event = WearEvent(outfitId: outfit.id)
                    modelContext.insert(event)
                    try? modelContext.save()
                    loggedWearAt = Date()
                }
                .padding(.horizontal, SUSpace.lg)

                VStack(alignment: .leading, spacing: SUSpace.md) {
                    SUSectionHeader(title: "Items", count: items.count)
                        .padding(.horizontal, SUSpace.lg)

                    VStack(spacing: SUSpace.sm) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                SUItemCard(
                                    imagePath: item.thumbnailPath,
                                    title: item.name,
                                    subtitle: item.subcategory.isEmpty ? item.category.displayName : item.subcategory
                                ) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundStyle(Color.suInkTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, SUSpace.lg)
                }

                Color.clear.frame(height: 100)
            }
            .padding(.top, SUSpace.md)
        }
        .background(Color.suCanvas.ignoresSafeArea())
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
                    .foregroundStyle(Color.suInkPrimary)
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
