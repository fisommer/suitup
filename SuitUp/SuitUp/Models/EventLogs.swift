import Foundation
import SwiftData

@Model
final class WearEvent {
    @Attribute(.unique) var id: UUID
    var itemId: UUID?
    var outfitId: UUID?
    var timestamp: Date

    init(id: UUID = UUID(), itemId: UUID? = nil, outfitId: UUID? = nil) {
        self.id = id
        self.itemId = itemId
        self.outfitId = outfitId
        self.timestamp = Date()
    }
}

@Model
final class StylingRequest {
    @Attribute(.unique) var id: UUID
    var itemId: UUID
    var contextOccasion: String?
    var contextWeather: String?
    var closetSnapshotIds: [UUID]
    var suggestionsJSON: Data
    var modelCostUSD: Double?
    var timestamp: Date

    init(
        id: UUID = UUID(),
        itemId: UUID,
        contextOccasion: String? = nil,
        contextWeather: String? = nil,
        closetSnapshotIds: [UUID],
        suggestionsJSON: Data,
        modelCostUSD: Double? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.contextOccasion = contextOccasion
        self.contextWeather = contextWeather
        self.closetSnapshotIds = closetSnapshotIds
        self.suggestionsJSON = suggestionsJSON
        self.modelCostUSD = modelCostUSD
        self.timestamp = Date()
    }
}
