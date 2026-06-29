import SwiftUI
import UIKit

/// Renders a collage thumbnail for a set of items. Built once per appearance,
/// not recomputed during scroll.
struct CollageThumb: View {
    let items: [Item]
    var size: CGSize = CGSize(width: 280, height: 350)

    @State private var collage: UIImage?

    var body: some View {
        Group {
            if let collage {
                Image(uiImage: collage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    Color(.tertiarySystemBackground)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task(id: items.map(\.id)) {
            collage = CollageRenderer.render(items: items, size: size)
        }
    }
}
