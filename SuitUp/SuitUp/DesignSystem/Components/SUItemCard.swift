import SwiftUI

/// Horizontal list-row card: thumbnail + title + caption. Used by Recreate history, Wishlist.
struct SUItemCard: View {
    let imagePath: String
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    init(
        imagePath: String,
        title: String,
        subtitle: String? = nil
    ) {
        self.imagePath = imagePath
        self.title = title
        self.subtitle = subtitle
        self.trailing = nil
    }

    init<Trailing: View>(
        imagePath: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.imagePath = imagePath
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: SUSpace.md) {
            StoredImage(relativePath: imagePath, contentMode: .fill)
                .frame(width: 56, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous))
                .background(Color.suSurfaceMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Inter Variable", size: 14).weight(.medium))
                    .foregroundStyle(Color.suInkPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .suCaption()
                        .foregroundStyle(Color.suInkTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                trailing
            }
        }
        .padding(SUSpace.md)
        .background(Color.suSurface)
        .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                .strokeBorder(Color.suBorder, lineWidth: 1)
        )
    }
}

#Preview("SUItemCard") {
    VStack(spacing: SUSpace.sm) {
        SUItemCard(imagePath: "", title: "Cream linen shirt", subtitle: "COS · Summer")
        SUItemCard(imagePath: "", title: "Black knit", subtitle: "Uniqlo · Winter") {
            Image(systemName: "chevron.right")
                .foregroundStyle(Color.suInkTertiary)
        }
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
