import Foundation
import SwiftData

@Model
final class WantedPiece {
    @Attribute(.unique) var id: UUID
    var pieceDescription: String
    var categoryRaw: String
    var colors: [String]
    var sourceRecreateAttemptId: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        pieceDescription: String,
        category: ItemCategory,
        colors: [String],
        sourceRecreateAttemptId: UUID
    ) {
        self.id = id
        self.pieceDescription = pieceDescription
        self.categoryRaw = category.rawValue
        self.colors = colors
        self.sourceRecreateAttemptId = sourceRecreateAttemptId
        self.createdAt = Date()
    }

    var category: ItemCategory { ItemCategory(rawValue: categoryRaw) ?? .top }
}
