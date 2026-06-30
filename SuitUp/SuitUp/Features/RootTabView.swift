import SwiftUI

/// Root tab container. Hosts the 4 main tabs and a floating SUTabBar over them.
/// The center FAB on the tab bar opens the universal add-item sheet.
struct RootTabView: View {
    @State private var selectedIndex: Int = 0
    @State private var showingAddSheet = false

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

            SUTabBar(tabs: tabs, selectedIndex: $selectedIndex, onFABTap: { showingAddSheet = true })
                .padding(.horizontal, SUSpace.lg)
                .padding(.bottom, SUSpace.sm)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddItemSourceSheet()
        }
    }
}

#Preview {
    RootTabView()
}
