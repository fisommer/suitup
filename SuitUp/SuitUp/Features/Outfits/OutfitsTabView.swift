import SwiftUI
import SwiftData

struct OutfitsTabView: View {
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No saved outfits yet",
                systemImage: "square.stack",
                description: Text("Save AI suggestions or build your own.")
            )
            .navigationTitle("Outfits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) { Image(systemName: "plus") }
                }
            }
        }
    }
}

#Preview {
    OutfitsTabView()
        .modelContainer(for: Outfit.self, inMemory: true)
}
