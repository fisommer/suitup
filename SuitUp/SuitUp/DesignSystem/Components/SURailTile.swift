import SwiftUI

/// A horizontal closet-rail tile: image fill, label at bottom, optional selected state.
struct SURailTile: View {
    let imagePath: String
    let label: String
    var subtitle: String? = nil
    var isSelected: Bool = false
    var size: CGSize = CGSize(width: 110, height: 140)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            StoredImage(relativePath: imagePath, contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()

            // Bottom gradient for label legibility
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 50)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.custom("Inter Variable", size: 11).weight(.semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.custom("Inter Variable", size: 10))
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Color.white)
            .padding(8)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.suSurfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                .strokeBorder(isSelected ? Color.suAccent : .clear, lineWidth: 2.5)
        )
        .animation(SUMotion.fast, value: isSelected)
    }
}

#Preview("SURailTile") {
    HStack(spacing: SUSpace.md) {
        SURailTile(imagePath: "", label: "Linen shirt", subtitle: "Summer · Loose")
        SURailTile(imagePath: "", label: "Wool blazer", isSelected: true)
        SURailTile(imagePath: "", label: "Oxford")
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
