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
                                            RailItemTile(item: item, isHighlighted: item.id == highlightedItemId)
                                        }
                                        .buttonStyle(.plain)
                                        .id(item.id)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: highlightedItemId) { _, newId in
                guard let newId else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
        }
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
        }
    }
}

private struct RailItemTile: View {
    let item: Item
    var isHighlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StoredImage(relativePath: item.thumbnailPath, contentMode: .fit)
                .frame(width: 110, height: 140)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor, lineWidth: isHighlighted ? 3 : 0)
                )
                .scaleEffect(isHighlighted ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: isHighlighted)
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)
        }
    }
}
