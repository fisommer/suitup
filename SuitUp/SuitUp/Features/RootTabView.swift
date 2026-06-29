import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ClosetTabView()
                .tabItem { Label("Closet", systemImage: "hanger") }
            OutfitsTabView()
                .tabItem { Label("Outfits", systemImage: "square.stack") }
            ReferencesTabView()
                .tabItem { Label("References", systemImage: "sparkles") }
            RecreateTabView()
                .tabItem { Label("Recreate", systemImage: "wand.and.stars") }
        }
    }
}

#Preview {
    RootTabView()
}
