import SwiftUI

struct ClosetRailsView: View {
    let items: [Item]

    private static let categoryOrder: [ItemCategory] = [.outerwear, .top, .bottom, .footwear, .accessory, .fullBody]

    private var grouped: [(ItemCategory, [Item])] {
        Self.categoryOrder.compactMap { cat in
            let group = items.filter { $0.category == cat }
            return group.isEmpty ? nil : (cat, group)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(grouped, id: \.0) { (category, items) in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.displayName)
                            .font(.headline)
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(items) { item in
                                    NavigationLink(value: item) {
                                        RailItemTile(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
        }
    }
}

private struct RailItemTile: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StoredImage(relativePath: item.thumbnailPath, contentMode: .fit)
                .frame(width: 110, height: 140)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)
        }
    }
}
