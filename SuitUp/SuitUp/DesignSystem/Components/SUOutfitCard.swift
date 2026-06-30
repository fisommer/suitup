import SwiftUI

/// Outfits grid card. Square-ish, image-dominant, optional caption row.
struct SUOutfitCard: View {
    let imagePath: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: SUSpace.sm) {
            StoredImage(relativePath: imagePath, contentMode: .fill)
                .aspectRatio(4/5, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .background(Color.suSurfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
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
        }
    }
}

#Preview("SUOutfitCard") {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: SUSpace.md), GridItem(.flexible(), spacing: SUSpace.md)], spacing: SUSpace.md) {
        SUOutfitCard(imagePath: "", title: "Linen Saturday", subtitle: "5 pieces")
        SUOutfitCard(imagePath: "", title: "Office cool", subtitle: "4 pieces")
        SUOutfitCard(imagePath: "", title: "Date night")
        SUOutfitCard(imagePath: "", title: "Sunday hike")
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
