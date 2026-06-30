import SwiftUI
import SwiftData

struct ClosetTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @Query(sort: \WantedPiece.createdAt, order: .reverse) private var wanted: [WantedPiece]
    @State private var showingSettings = false
    @State private var showingAddSheet = false
    @StateObject private var events = AppEvents.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.suCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: headerHeight)

                        if items.isEmpty {
                            VStack {
                                Spacer(minLength: 40)
                                SUEmptyState(
                                    icon: "hanger",
                                    title: "Your closet is empty",
                                    message: "Add your first piece — by photo, paste a link, or the share sheet from any product page.",
                                    actionTitle: "Add item",
                                    action: { showingAddSheet = true }
                                )
                                #if DEBUG
                                devSeedButton
                                    .padding(.top, SUSpace.md)
                                #endif
                                Spacer(minLength: 40)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            ClosetRailsView(items: items, highlightedItemId: events.lastSavedItemId)

                            if !wanted.isEmpty {
                                wishlistRail
                                    .padding(.top, SUSpace.xl)
                            }
                            #if DEBUG
                            HStack {
                                Spacer()
                                devWipeButton
                                Spacer()
                            }
                            .padding(.top, SUSpace.xl)
                            #endif
                        }

                        Color.clear.frame(height: 100)
                    }
                }

                // Floating header
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

                if events.showSavedToast {
                    SUToast(message: "Saved \(events.lastSavedItemName ?? "")")
                        .padding(.top, headerHeight + SUSpace.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(SUMotion.standard, value: events.showSavedToast)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAddSheet) {
                AddItemSourceSheet()
            }
        }
    }

    private var headerHeight: CGFloat { 80 }

    /// "Wishlist" rail at the bottom of the Closet. Shows wanted pieces (from Recreate
    /// missing matches). Visually distinct from real items — dashed border, no photo.
    private var wishlistRail: some View {
        VStack(alignment: .leading, spacing: SUSpace.md) {
            SUSectionHeader(title: "Wishlist", count: wanted.count)
                .padding(.horizontal, SUSpace.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SUSpace.md) {
                    ForEach(wanted) { w in
                        wishlistTile(w)
                    }
                }
                .padding(.horizontal, SUSpace.lg)
            }
        }
    }

    private func wishlistTile(_ w: WantedPiece) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                    .fill(Color.suSurfaceMuted)
                    .frame(width: 110, height: 140)
                Image(systemName: "bookmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.suInkTertiary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                    .strokeBorder(Color.suBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )

            Text(w.pieceDescription)
                .font(.custom("Inter Variable", size: 11).weight(.medium))
                .foregroundStyle(Color.suInkPrimary)
                .lineLimit(2)
                .frame(width: 110, alignment: .leading)

            Text(w.category.displayName)
                .suCaption()
                .foregroundStyle(Color.suInkTertiary)
                .frame(width: 110, alignment: .leading)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Closet")
                .suTitle()
                .foregroundStyle(Color.suInkPrimary)

            Spacer()

            Button { showingSettings = true } label: {
                ZStack {
                    Circle()
                        .fill(Color.suSurface)
                        .frame(width: 36, height: 36)
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Color.suInkPrimary)
                }
                .overlay(Circle().strokeBorder(Color.suBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    #if DEBUG
    private var devSeedButton: some View {
        Button {
            SeedData.seed(modelContext: modelContext)
        } label: {
            Label("Dev: Seed sample closet", systemImage: "sparkles")
                .font(.custom("Inter Variable", size: 12))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var devWipeButton: some View {
        Button(role: .destructive) {
            SeedData.wipe(modelContext: modelContext, items: items)
        } label: {
            Label("Dev: Wipe closet", systemImage: "trash")
                .font(.custom("Inter Variable", size: 12))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
    #endif
}

#Preview {
    ClosetTabView()
        .modelContainer(for: Item.self, inMemory: true)
}
