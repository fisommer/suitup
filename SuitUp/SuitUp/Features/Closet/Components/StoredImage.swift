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
                Color.gray.opacity(0.12)
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
