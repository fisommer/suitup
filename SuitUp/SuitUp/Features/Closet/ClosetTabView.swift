import SwiftUI
import SwiftData

struct ClosetTabView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Your closet is empty",
                systemImage: "hanger",
                description: Text("Tap + to add your first piece.")
            )
            .navigationTitle("Closet")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {}) { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) { Image(systemName: "plus") }
                }
            }
        }
    }
}

#Preview {
    ClosetTabView()
        .modelContainer(for: Item.self, inMemory: true)
}
