import SwiftUI
import SwiftData

struct OutfitsTabView: View {
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @State private var showingBuilder = false

    private let cols = [
        GridItem(.flexible(), spacing: SUSpace.md),
        GridItem(.flexible(), spacing: SUSpace.md),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.suCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: headerHeight)

                        if outfits.isEmpty {
                            VStack {
                                Spacer(minLength: 40)
                                SUEmptyState(
                                    icon: "square.stack",
                                    title: "No saved outfits yet",
                                    message: "Save AI suggestions from \"Style this piece\", or build your own with the + button.",
                                    actionTitle: "Build an outfit",
                                    action: { showingBuilder = true }
                                )
                                Spacer(minLength: 40)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: cols, spacing: SUSpace.md) {
                                ForEach(outfits) { outfit in
                                    NavigationLink(value: outfit) {
                                        SUOutfitCard(
                                            imagePath: outfit.coverImagePath,
                                            title: outfit.name,
                                            subtitle: "\(outfit.itemIds.count) piece\(outfit.itemIds.count == 1 ? "" : "s")"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, SUSpace.lg)
                        }

                        Color.clear.frame(height: 100)
                    }
                }
                .navigationDestination(for: Outfit.self) { outfit in
                    OutfitDetailView(outfit: outfit)
                }

                headerRow
                    .padding(.horizontal, SUSpace.lg)
                    .padding(.top, SUSpace.md)
                    .padding(.bottom, SUSpace.lg)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.suCanvas
                            .opacity(0.92)
                            .background(.ultraThinMaterial)
                    )
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingBuilder) {
                OutfitBuilderView()
            }
        }
    }

    private var headerHeight: CGFloat { 80 }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Outfits")
                .suTitle()
                .foregroundStyle(Color.suInkPrimary)
            Spacer()
        }
    }
}

#Preview {
    OutfitsTabView()
        .modelContainer(for: Outfit.self, inMemory: true)
}
