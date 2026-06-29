import SwiftUI
import SwiftData

struct ReferencesTabView: View {
    @Query(sort: \ReferenceLook.createdAt, order: .reverse) private var refs: [ReferenceLook]

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No references yet",
                systemImage: "sparkles",
                description: Text("Save outfits you love to teach SuitUp your taste.")
            )
            .navigationTitle("References")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {}) { Image(systemName: "plus") }
                }
            }
        }
    }
}

#Preview {
    ReferencesTabView()
        .modelContainer(for: ReferenceLook.self, inMemory: true)
}
