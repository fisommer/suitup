import SwiftUI
import SwiftData

struct ReferencesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReferenceLook.createdAt, order: .reverse) private var refs: [ReferenceLook]
    @State private var showingAdd = false

    private let cols = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if refs.isEmpty {
                    ContentUnavailableView(
                        "No references yet",
                        systemImage: "sparkles",
                        description: Text("Save 15–30 outfits you love to teach SuitUp your taste.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 4) {
                            ForEach(refs) { ref in
                                NavigationLink(value: ref) {
                                    StoredImage(relativePath: ref.thumbnailPath, contentMode: .fill)
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipped()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .navigationDestination(for: ReferenceLook.self) {
                        ReferenceDetailView(ref: $0)
                    }
                }
            }
            .navigationTitle("References")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddReferenceSheet()
            }
        }
    }
}

#Preview {
    ReferencesTabView()
        .modelContainer(for: ReferenceLook.self, inMemory: true)
}
