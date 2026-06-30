import SwiftUI

/// Root tab container. Hosts the 4 main tabs and a floating SUTabBar over them.
/// The center FAB on the tab bar is context-aware:
///   - Closet tab → opens the closet add-source sheet
///   - References tab → opens AddReferenceSheet directly
///   - Outfits tab → opens OutfitBuilderView (manual outfit builder)
///   - Recreate tab → opens NewRecreateSheet directly
struct RootTabView: View {
    @State private var selectedIndex: Int = 0
    @State private var showingAddClosetSheet = false
    @State private var showingAddReferenceSheet = false
    @State private var showingOutfitBuilder = false
    @State private var showingNewRecreateSheet = false

    private let tabs: [SUTabBar.TabItem] = [
        .init(title: "Closet",   icon: "hanger"),
        .init(title: "Refs",     icon: "sparkles"),
        .init(title: "Outfits",  icon: "square.stack", filledIcon: "square.stack.fill"),
        .init(title: "Recreate", icon: "wand.and.stars")
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedIndex {
                case 0: ClosetTabView()
                case 1: ReferencesTabView()
                case 2: OutfitsTabView()
                case 3: RecreateTabView()
                default: ClosetTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.suCanvas)
            .ignoresSafeArea(edges: .bottom)

            SUTabBar(tabs: tabs, selectedIndex: $selectedIndex, onFABTap: handleFABTap)
                .padding(.horizontal, SUSpace.lg)
                .padding(.bottom, SUSpace.sm)
        }
        .sheet(isPresented: $showingAddClosetSheet) {
            AddItemSourceSheet()
        }
        .sheet(isPresented: $showingAddReferenceSheet) {
            AddReferenceSheet()
        }
        .sheet(isPresented: $showingOutfitBuilder) {
            OutfitBuilderView()
        }
        .sheet(isPresented: $showingNewRecreateSheet) {
            NewRecreateSheet()
        }
    }

    private func handleFABTap() {
        switch selectedIndex {
        case 1: showingAddReferenceSheet = true
        case 2: showingOutfitBuilder = true
        case 3: showingNewRecreateSheet = true
        default: showingAddClosetSheet = true
        }
    }
}

#Preview {
    RootTabView()
}
