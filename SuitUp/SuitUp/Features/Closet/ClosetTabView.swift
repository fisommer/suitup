import SwiftUI
import SwiftData

struct ClosetTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var showingSettings = false
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
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

                #if DEBUG
                devControls
                    .padding(.bottom, 8)
                #endif
            }
            .navigationTitle("Closet")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAddSheet) {
                AddItemSourceSheet()
            }
        }
    }

    #if DEBUG
    @ViewBuilder
    private var devControls: some View {
        if items.isEmpty {
            Button {
                SeedData.seed(modelContext: modelContext)
            } label: {
                Label("Dev: Seed sample closet", systemImage: "sparkles")
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        } else {
            Button(role: .destructive) {
                SeedData.wipe(modelContext: modelContext, items: items)
            } label: {
                Label("Dev: Wipe closet", systemImage: "trash")
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
    #endif
}

#Preview {
    ClosetTabView()
        .modelContainer(for: Item.self, inMemory: true)
}
