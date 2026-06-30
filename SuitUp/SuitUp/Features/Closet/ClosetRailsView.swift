import SwiftUI

struct ClosetRailsView: View {
    let items: [Item]
    var highlightedItemId: UUID? = nil

    private static let categoryOrder: [ItemCategory] = [.outerwear, .top, .bottom, .footwear, .accessory, .fullBody]

    private var grouped: [(ItemCategory, [Item])] {
        Self.categoryOrder.compactMap { cat in
            let group = items
                .filter { $0.category == cat }
                // Loved items first, then by date added (newest first)
                .sorted { lhs, rhs in
                    if lhs.isLoved != rhs.isLoved { return lhs.isLoved && !rhs.isLoved }
                    return lhs.createdAt > rhs.createdAt
                }
            return group.isEmpty ? nil : (cat, group)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: SUSpace.xl) {
                ForEach(grouped, id: \.0) { (category, items) in
                    VStack(alignment: .leading, spacing: SUSpace.md) {
                        NavigationLink(value: category) {
                            SUSectionHeader(title: category.displayName, count: items.count)
                                .overlay(alignment: .trailing) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .light))
                                        .foregroundStyle(Color.suInkTertiary)
                                }
                                .padding(.horizontal, SUSpace.lg)
                        }
                        .buttonStyle(.plain)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SUSpace.md) {
                                ForEach(items) { item in
                                    NavigationLink(value: item) {
                                        ZStack(alignment: .topTrailing) {
                                            SURailTile(
                                                imagePath: item.thumbnailPath,
                                                label: item.name,
                                                subtitle: nil,
                                                isSelected: item.id == highlightedItemId
                                            )
                                            if item.isLoved {
                                                Image(systemName: "heart.fill")
                                                    .font(.system(size: 11, weight: .light))
                                                    .foregroundStyle(Color.suAccent)
                                                    .padding(6)
                                                    .background(Color.black.opacity(0.35))
                                                    .clipShape(Circle())
                                                    .padding(6)
                                            }
                                        }
                                        .scaleEffect(item.id == highlightedItemId ? 1.04 : 1.0)
                                        .animation(SUMotion.standard, value: highlightedItemId)
                                    }
                                    .buttonStyle(.plain)
                                    .id(item.id)
                                }
                            }
                            .padding(.horizontal, SUSpace.lg)
                        }
                    }
                }
            }
            .onChange(of: highlightedItemId) { _, newId in
                guard let newId else { return }
                withAnimation(SUMotion.standard) {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
        }
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
        }
        .navigationDestination(for: ItemCategory.self) { category in
            CategoryDetailView(category: category)
        }
    }
}
