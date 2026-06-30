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
            VStack(alignment: .leading, spacing: SUSpace.lg) {
                imageGallery
                    .frame(maxWidth: .infinity)
                    .frame(height: 380)
                    .background(Color.suSurfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SURadius.lg, style: .continuous))
                    .padding(.horizontal, SUSpace.lg)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .suTitle()
                        .foregroundStyle(Color.suInkPrimary)
                    Text(metaLine)
                        .suCaption()
                        .foregroundStyle(Color.suInkSecondary)
                }
                .padding(.horizontal, SUSpace.lg)

                if !attributeTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SUSpace.sm) {
                            ForEach(attributeTags, id: \.title) { tag in
                                SUTag(tag.title, style: tag.style)
                            }
                        }
                        .padding(.horizontal, SUSpace.lg)
                    }
                }

                SUButton("Style this piece", icon: "sparkles") {
                    showingStyling = true
                }
                .padding(.horizontal, SUSpace.lg)
                .padding(.top, SUSpace.xs)

                detailsList

                // Bottom inset so content clears the floating tab bar
                Color.clear.frame(height: 100)
            }
            .padding(.top, SUSpace.md)
        }
        .background(Color.suCanvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button(role: .destructive) { showingDeleteConfirm = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color.suInkPrimary)
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

    private var metaLine: String {
        var parts: [String] = []
        if !item.subcategory.isEmpty {
            parts.append(item.subcategory)
        } else {
            parts.append(item.category.displayName)
        }
        if let brand = item.brand, !brand.isEmpty {
            parts.append(brand)
        }
        if let price = item.price {
            parts.append("€\(NSDecimalNumber(decimal: price).stringValue)")
        }
        return parts.joined(separator: " · ")
    }

    private var attributeTags: [(title: String, style: SUTag.Style)] {
        var tags: [(String, SUTag.Style)] = []
        item.seasons.forEach { tags.append(($0.rawValue.capitalized, .neutral)) }
        if let fit = item.fit {
            tags.append((fit.rawValue.capitalized, .neutral))
        }
        tags.append((item.formality.rawValue.capitalized, .accent))
        return tags
    }

    @ViewBuilder
    private var detailsList: some View {
        VStack(alignment: .leading, spacing: SUSpace.md) {
            DetailRow(label: "Category", value: item.category.displayName)
            if !item.colors.isEmpty {
                DetailRow(label: "Colors", value: item.colors.joined(separator: ", "))
            }
            if !item.seasons.isEmpty {
                DetailRow(label: "Seasons", value: item.seasons.map(\.rawValue.capitalized).joined(separator: ", "))
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
        .padding(.horizontal, SUSpace.lg)
    }

    @ViewBuilder
    private var imageGallery: some View {
        let paths = [item.imagePath] + item.additionalImagePaths
        if paths.count <= 1 {
            StoredImage(relativePath: item.imagePath, contentMode: .fit)
        } else {
            TabView {
                ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                    StoredImage(relativePath: path, contentMode: .fit)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .suLabel()
                .foregroundStyle(Color.suInkTertiary)
            Text(value)
                .suBody()
                .foregroundStyle(Color.suInkPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
