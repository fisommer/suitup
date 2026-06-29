import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false
    @State private var showingStyling = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StoredImage(relativePath: item.imagePath, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .background(Color(.secondarySystemBackground))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.title2.bold())
                    Text("\(item.subcategory.isEmpty ? item.category.displayName : item.subcategory) · \(item.formality.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Button {
                    showingStyling = true
                } label: {
                    Label("Style this piece", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                DetailRow(label: "Category", value: item.category.displayName)
                if !item.colors.isEmpty {
                    DetailRow(label: "Colors", value: item.colors.joined(separator: ", "))
                }
                if !item.seasons.isEmpty {
                    DetailRow(label: "Seasons", value: item.seasons.map(\.rawValue).joined(separator: ", "))
                }
                if let brand = item.brand, !brand.isEmpty {
                    DetailRow(label: "Brand", value: brand)
                }
                if let size = item.size, !size.isEmpty {
                    DetailRow(label: "Size", value: size)
                }
                if let material = item.material, !material.isEmpty {
                    DetailRow(label: "Material", value: material)
                }
                if let pattern = item.pattern, !pattern.isEmpty {
                    DetailRow(label: "Pattern", value: pattern)
                }
                if let notes = item.notes, !notes.isEmpty {
                    DetailRow(label: "Notes", value: notes)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button(role: .destructive) { showingDeleteConfirm = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                ImageStore.delete(item.imagePath)
                ImageStore.delete(item.thumbnailPath)
                ImageStore.delete(item.originalImagePath)
                item.additionalImagePaths.forEach { ImageStore.delete($0) }
                modelContext.delete(item)
                try? modelContext.save()
                dismiss()
            }
        }
        .sheet(isPresented: $showingStyling) {
            StylingView(selected: item)
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
