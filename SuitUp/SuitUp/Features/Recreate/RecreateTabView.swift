import SwiftUI
import SwiftData

struct RecreateTabView: View {
    @Query(sort: \RecreateAttempt.createdAt, order: .reverse) private var attempts: [RecreateAttempt]

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No recreate attempts yet",
                systemImage: "wand.and.stars",
                description: Text("Share an outfit image to see what you can recreate.")
            )
            .navigationTitle("Recreate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) { Image(systemName: "plus") }
                }
            }
        }
    }
}

#Preview {
    RecreateTabView()
        .modelContainer(for: RecreateAttempt.self, inMemory: true)
}
