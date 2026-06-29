import Foundation
import SwiftData

enum ReferenceSource: String, Codable {
    case library, urlCrawl, shareSheet
}

@Model
final class ReferenceLook {
    @Attribute(.unique) var id: UUID
    var imagePath: String
    var thumbnailPath: String
    var sourceRaw: String
    var sourceUrl: String?
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        imagePath: String,
        thumbnailPath: String,
        source: ReferenceSource,
        sourceUrl: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
        self.sourceRaw = source.rawValue
        self.sourceUrl = sourceUrl
        self.note = note
        self.createdAt = Date()
    }

    var source: ReferenceSource { ReferenceSource(rawValue: sourceRaw) ?? .library }
}
