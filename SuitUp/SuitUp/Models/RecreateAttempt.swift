import Foundation
import SwiftData

enum MatchStatus: String, Codable { case matched, missing }
enum MatchConfidence: String, Codable { case veryClose, close, loose }

struct ParsedPiece: Codable, Hashable {
    let description: String
    let category: ItemCategory
    let colors: [String]
    let formality: Formality?
}

struct PieceMatch: Codable, Hashable {
    let pieceIndex: Int
    let status: MatchStatus
    /// Primary match (for backwards compat / quick access). Use `matchedItemIds` for the full list.
    let matchedItemId: UUID?
    /// All closet items that match this piece. The first element is the "best" match.
    /// Older saved attempts may have just one element here.
    var matchedItemIds: [UUID]
    let confidence: MatchConfidence?
    let note: String?
    var wantedPieceId: UUID?

    init(
        pieceIndex: Int,
        status: MatchStatus,
        matchedItemId: UUID? = nil,
        matchedItemIds: [UUID]? = nil,
        confidence: MatchConfidence? = nil,
        note: String? = nil,
        wantedPieceId: UUID? = nil
    ) {
        self.pieceIndex = pieceIndex
        self.status = status
        // Reconcile single + array inputs so callers can pass either.
        if let matchedItemIds, !matchedItemIds.isEmpty {
            self.matchedItemIds = matchedItemIds
            self.matchedItemId = matchedItemIds.first
        } else if let matchedItemId {
            self.matchedItemIds = [matchedItemId]
            self.matchedItemId = matchedItemId
        } else {
            self.matchedItemIds = []
            self.matchedItemId = nil
        }
        self.confidence = confidence
        self.note = note
        self.wantedPieceId = wantedPieceId
    }

    enum CodingKeys: String, CodingKey {
        case pieceIndex, status, matchedItemId, matchedItemIds, confidence, note, wantedPieceId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.pieceIndex = try c.decode(Int.self, forKey: .pieceIndex)
        self.status = try c.decode(MatchStatus.self, forKey: .status)
        self.confidence = try c.decodeIfPresent(MatchConfidence.self, forKey: .confidence)
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
        self.wantedPieceId = try c.decodeIfPresent(UUID.self, forKey: .wantedPieceId)
        // Prefer matchedItemIds; fall back to singular for older saved attempts.
        if let ids = try c.decodeIfPresent([UUID].self, forKey: .matchedItemIds), !ids.isEmpty {
            self.matchedItemIds = ids
            self.matchedItemId = ids.first
        } else if let id = try c.decodeIfPresent(UUID.self, forKey: .matchedItemId) {
            self.matchedItemIds = [id]
            self.matchedItemId = id
        } else {
            self.matchedItemIds = []
            self.matchedItemId = nil
        }
    }
}

@Model
final class RecreateAttempt {
    @Attribute(.unique) var id: UUID
    var name: String?
    var sourceImagePath: String
    var sourceUrl: String?
    var parsedPiecesJSON: Data
    var matchesJSON: Data
    var recreatableCount: Int
    var totalPieceCount: Int
    var linkedReferenceLookId: UUID?
    var savedOutfitId: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String? = nil,
        sourceImagePath: String,
        sourceUrl: String? = nil,
        parsedPieces: [ParsedPiece],
        matches: [PieceMatch],
        linkedReferenceLookId: UUID? = nil,
        savedOutfitId: UUID? = nil
    ) throws {
        self.id = id
        self.name = name
        self.sourceImagePath = sourceImagePath
        self.sourceUrl = sourceUrl
        self.parsedPiecesJSON = try JSONEncoder().encode(parsedPieces)
        self.matchesJSON = try JSONEncoder().encode(matches)
        self.totalPieceCount = parsedPieces.count
        self.recreatableCount = matches.filter { $0.status == .matched }.count
        self.linkedReferenceLookId = linkedReferenceLookId
        self.savedOutfitId = savedOutfitId
        self.createdAt = Date()
    }

    var parsedPieces: [ParsedPiece] {
        (try? JSONDecoder().decode([ParsedPiece].self, from: parsedPiecesJSON)) ?? []
    }
    var matches: [PieceMatch] {
        (try? JSONDecoder().decode([PieceMatch].self, from: matchesJSON)) ?? []
    }
}
