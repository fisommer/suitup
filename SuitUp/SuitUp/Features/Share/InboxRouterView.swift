import SwiftUI
import UIKit

/// Routes a single shared payload (received from SuitUpShareExtension via the App Group inbox)
/// to the appropriate existing flow sheet, with the image or URL preloaded.
///
/// Action values written by the extension:
///   - "reference"    → AddReferenceSheet(preloadedImage:)
///   - "recreate"     → NewRecreateSheet(preloadedImage:)
///   - "closet-url"   → PasteURLView(prefilledURL:)
///
/// On dismiss, this view deletes the companion image file from the App Group inbox.
struct InboxRouterView: View {
    let item: InboxItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch item.action {
            case "reference":
                AddReferenceSheet(preloadedImage: loadedImage())
            case "recreate":
                NewRecreateSheet(preloadedImage: loadedImage(), prefilledName: nil)
            case "closet-url":
                PasteURLView(prefilledURL: item.url)
            default:
                unknownActionView
            }
        }
        .onDisappear { cleanupImageFile() }
    }

    private var unknownActionView: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Unknown shared action: \(item.action)")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Dismiss") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func loadedImage() -> UIImage? {
        guard let fileName = item.imageFileName else { return nil }
        let url = SharedContainer.inboxURL().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func cleanupImageFile() {
        guard let fileName = item.imageFileName else { return }
        let url = SharedContainer.inboxURL().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}
