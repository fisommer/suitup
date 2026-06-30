import SwiftUI

/// Section label row: uppercase title on the left, optional action link on the right.
struct SUSectionHeader: View {
    let title: String
    var count: Int? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                    .suLabel()
                    .foregroundStyle(Color.suInkTertiary)
                if let count {
                    Text("· \(count)")
                        .suLabel()
                        .foregroundStyle(Color.suInkTertiary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                            .font(.custom("Inter Variable", size: 12).weight(.medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.suAccentDeep)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview("SUSectionHeader") {
    VStack(spacing: SUSpace.lg) {
        SUSectionHeader(title: "Tops", count: 12)
        SUSectionHeader(title: "Outerwear", count: 4, actionTitle: "See all") {}
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
