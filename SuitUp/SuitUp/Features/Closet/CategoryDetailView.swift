import SwiftUI
import SwiftData

/// Detail view for one closet category — Pinterest-style grid showing all items in that category.
/// Accessible via tap on a category header in ClosetRailsView.
struct CategoryDetailView: View {
    let category: ItemCategory
    @Query private var allItems: [Item]

    private var items: [Item] {
        allItems
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                if lhs.isLoved != rhs.isLoved { return lhs.isLoved && !rhs.isLoved }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// Pinterest-style alternating split: even-index → left, odd → right.
    private var leftColumn: [Item] {
        items.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }
    }
    private var rightColumn: [Item] {
        items.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(category.displayName)
                        .suTitle()
                        .foregroundStyle(Color.suInkPrimary)
                    Text("·  \(items.count)")
                        .suTitle()
                        .foregroundStyle(Color.suInkTertiary)
                    Spacer()
                }
                .padding(.horizontal, SUSpace.lg)
                .padding(.top, SUSpace.md)
                .padding(.bottom, SUSpace.lg)

                HStack(alignment: .top, spacing: SUSpace.md) {
                    masonryColumn(items: leftColumn)
                    masonryColumn(items: rightColumn)
                }
                .padding(.horizontal, SUSpace.lg)

                Color.clear.frame(height: 100)
            }
        }
        .background(Color.suCanvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func masonryColumn(items: [Item]) -> some View {
        VStack(spacing: SUSpace.md) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: SUSpace.sm) {
                            StoredImage(relativePath: item.thumbnailPath, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .background(Color.suSurfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.custom("Inter Variable", size: 13).weight(.medium))
                                    .foregroundStyle(Color.suInkPrimary)
                                    .lineLimit(1)
                                if let brand = item.brand, !brand.isEmpty {
                                    Text(brand)
                                        .suCaption()
                                        .foregroundStyle(Color.suInkTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                        if item.isLoved {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(Color.suAccent)
                                .padding(6)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Circle())
                                .padding(8)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
