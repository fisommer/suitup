import SwiftUI

/// Floating pill-shaped tab bar. 4 nav tabs + center honey FAB.
/// The active tab gets a tiny gold underline that slides via matchedGeometryEffect.
struct SUTabBar: View {
    let tabs: [TabItem]
    @Binding var selectedIndex: Int
    var onFABTap: () -> Void = {}

    @Namespace private var indicatorNS

    struct TabItem: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let filledIcon: String?

        init(title: String, icon: String, filledIcon: String? = nil) {
            self.title = title
            self.icon = icon
            self.filledIcon = filledIcon
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.prefix(2).enumerated()), id: \.element.id) { (idx, tab) in
                tabButton(tab: tab, index: idx)
            }
            // FAB
            Button(action: onFABTap) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.suInkPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.suAccent)
                    .clipShape(Circle())
                    .suElevation(.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, SUSpace.sm)
            ForEach(Array(tabs.dropFirst(2).enumerated()), id: \.element.id) { (offsetIdx, tab) in
                tabButton(tab: tab, index: offsetIdx + 2)
            }
        }
        .padding(.horizontal, SUSpace.md)
        .padding(.vertical, 8)
        .background(Color.suSurface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.suBorder, lineWidth: 1))
        .suElevation(.e2)
    }

    @ViewBuilder
    private func tabButton(tab: TabItem, index: Int) -> some View {
        Button {
            withAnimation(SUMotion.standard) { selectedIndex = index }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: selectedIndex == index ? (tab.filledIcon ?? tab.icon) : tab.icon)
                    .font(.system(size: 17, weight: selectedIndex == index ? .regular : .light))
                Text(tab.title)
                    .font(.custom("Inter Variable", size: 10).weight(selectedIndex == index ? .semibold : .regular))
                ZStack {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: 16, height: 2)
                    if selectedIndex == index {
                        Capsule()
                            .fill(Color.suAccent)
                            .frame(width: 16, height: 2)
                            .matchedGeometryEffect(id: "indicator", in: indicatorNS)
                    }
                }
            }
            .foregroundStyle(selectedIndex == index ? Color.suInkPrimary : Color.suInkTertiary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview("SUTabBar") {
    @Previewable @State var idx = 0
    VStack {
        Spacer()
        SUTabBar(
            tabs: [
                .init(title: "Closet",   icon: "hanger"),
                .init(title: "Refs",     icon: "sparkles"),
                .init(title: "Outfits",  icon: "square.stack", filledIcon: "square.stack.fill"),
                .init(title: "Recreate", icon: "wand.and.stars")
            ],
            selectedIndex: $idx
        )
        .padding(.horizontal, SUSpace.lg)
        .padding(.bottom, SUSpace.lg)
    }
    .background(Color.suCanvas)
}
