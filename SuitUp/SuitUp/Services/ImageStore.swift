import Foundation
import UIKit

enum ImageStoreFolder: String {
    case items, references, outfits, recreate
}

enum ImageStoreError: Error, LocalizedError {
    case encodingFailed
    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Could not encode image as JPEG."
        }
    }
}

struct ImageStore {
    static func baseDir() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func folderURL(_ folder: ImageStoreFolder) -> URL {
        let url = baseDir().appendingPathComponent(folder.rawValue)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Save a UIImage as JPEG. Returns the relative path (from baseDir).
    @discardableResult
    static func save(
        _ image: UIImage,
        folder: ImageStoreFolder,
        name: String,
        quality: CGFloat = 0.85,
        maxDimension: CGFloat? = nil
    ) throws -> String {
        let resized = maxDimension.map { resize(image, maxDimension: $0) } ?? image
        guard let data = resized.jpegData(compressionQuality: quality) else {
            throw ImageStoreError.encodingFailed
        }
        let filename = "\(name).jpg"
        let url = folderURL(folder).appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return "\(folder.rawValue)/\(filename)"
    }

    static func load(_ relativePath: String) -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        let url = baseDir().appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: url.path)
    }

    static func delete(_ relativePath: String) {
        guard !relativePath.isEmpty else { return }
        let url = baseDir().appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
