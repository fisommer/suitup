import Foundation
import SwiftData

enum OutfitSource: String, Codable {
    case manuallyBuilt, savedFromStyling
}

@Model
final class Outfit {
    @Attribute(.unique) var id: UUID
    var name: String
    var itemIds: [UUID]
    var coverImagePath: String
    var sourceRaw: String
    var rationale: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        itemIds: [UUID],
        coverImagePath: String,
        source: OutfitSource,
        rationale: String? = nil,
        notes: String? = nil
    ) {
        let now = Date()
        self.id = id
        self.name = name
        self.itemIds = itemIds
        self.coverImagePath = coverImagePath
        self.sourceRaw = source.rawValue
        self.rationale = rationale
        self.notes = notes
        self.createdAt = now
        self.updatedAt = now
    }

    var source: OutfitSource { OutfitSource(rawValue: sourceRaw) ?? .manuallyBuilt }
}
