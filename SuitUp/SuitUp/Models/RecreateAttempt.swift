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
    let matchedItemId: UUID?
    let confidence: MatchConfidence?
    let note: String?
    var wantedPieceId: UUID?
}

@Model
final class RecreateAttempt {
    @Attribute(.unique) var id: UUID
    var sourceImagePath: String
    var sourceUrl: String?
    var parsedPiecesJSON: Data
    var matchesJSON: Data
    var recreatableCount: Int
    var totalPieceCount: Int
    var linkedReferenceLookId: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceImagePath: String,
        sourceUrl: String? = nil,
        parsedPieces: [ParsedPiece],
        matches: [PieceMatch],
        linkedReferenceLookId: UUID? = nil
    ) throws {
        self.id = id
        self.sourceImagePath = sourceImagePath
        self.sourceUrl = sourceUrl
        self.parsedPiecesJSON = try JSONEncoder().encode(parsedPieces)
        self.matchesJSON = try JSONEncoder().encode(matches)
        self.totalPieceCount = parsedPieces.count
        self.recreatableCount = matches.filter { $0.status == .matched }.count
        self.linkedReferenceLookId = linkedReferenceLookId
        self.createdAt = Date()
    }

    var parsedPieces: [ParsedPiece] {
        (try? JSONDecoder().decode([ParsedPiece].self, from: parsedPiecesJSON)) ?? []
    }
    var matches: [PieceMatch] {
        (try? JSONDecoder().decode([PieceMatch].self, from: matchesJSON)) ?? []
    }
}
