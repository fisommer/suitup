import SwiftUI

struct StoredImage: View {
    let relativePath: String
    var contentMode: ContentMode = .fit

    var body: some View {
        if let img = ImageStore.load(relativePath) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            ZStack {
                Color.suSurfaceMuted
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.suInkTertiary)
            }
        }
    }
}
