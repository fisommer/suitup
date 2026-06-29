import SwiftUI
import SwiftData

struct OutfitsTabView: View {
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @State private var showingBuilder = false

    private let cols = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if outfits.isEmpty {
                    ContentUnavailableView(
                        "No saved outfits yet",
                        systemImage: "square.stack",
                        description: Text("Save AI suggestions from \"Style this piece\", or build your own with the + button.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(outfits) { outfit in
                                NavigationLink(value: outfit) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        StoredImage(relativePath: outfit.coverImagePath, contentMode: .fit)
                                            .aspectRatio(4.0/5.0, contentMode: .fit)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        Text(outfit.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .navigationDestination(for: Outfit.self) { outfit in
                        OutfitDetailView(outfit: outfit)
                    }
                }
            }
            .navigationTitle("Outfits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingBuilder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingBuilder) {
                OutfitBuilderView()
            }
        }
    }
}

#Preview {
    OutfitsTabView()
        .modelContainer(for: Outfit.self, inMemory: true)
}
