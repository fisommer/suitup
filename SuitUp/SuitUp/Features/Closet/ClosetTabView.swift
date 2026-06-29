import SwiftUI
import SwiftData

struct ClosetTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Your closet is empty",
                        systemImage: "hanger",
                        description: Text("Tap + to add your first piece.")
                    )
                } else {
                    ClosetRailsView(items: items)
                }
            }
            .navigationTitle("Closet")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Add-item flow wired up in Phase 3.
                    Button {} label: {
                        Image(systemName: "plus")
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .bottomBar) {
                    if items.isEmpty {
                        Button("Dev: Seed sample closet") {
                            SeedData.seed(modelContext: modelContext)
                        }
                        .font(.caption)
                    } else {
                        Button("Dev: Wipe closet", role: .destructive) {
                            SeedData.wipe(modelContext: modelContext, items: items)
                        }
                        .font(.caption)
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    ClosetTabView()
        .modelContainer(for: Item.self, inMemory: true)
}
