import SwiftUI

struct ClosetRailsView: View {
    let items: [Item]
    var highlightedItemId: UUID? = nil

    private static let categoryOrder: [ItemCategory] = [.outerwear, .top, .bottom, .footwear, .accessory, .fullBody]

    private var grouped: [(ItemCategory, [Item])] {
        Self.categoryOrder.compactMap { cat in
            let group = items.filter { $0.category == cat }
            return group.isEmpty ? nil : (cat, group)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: SUSpace.xl) {
                ForEach(grouped, id: \.0) { (category, items) in
                    VStack(alignment: .leading, spacing: SUSpace.md) {
                        SUSectionHeader(title: category.displayName, count: items.count)
                            .padding(.horizontal, SUSpace.lg)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SUSpace.md) {
                                ForEach(items) { item in
                                    NavigationLink(value: item) {
                                        SURailTile(
                                            imagePath: item.thumbnailPath,
                                            label: item.name,
                                            subtitle: nil,
                                            isSelected: item.id == highlightedItemId
                                        )
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
    }
}
