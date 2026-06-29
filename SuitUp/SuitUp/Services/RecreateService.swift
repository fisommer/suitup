import Foundation
import UIKit

struct RecreateResult {
    let parsedPieces: [ParsedPiece]
    let matches: [PieceMatch]
}

enum RecreateError: Error, LocalizedError {
    case noPieces
    case anthropic(Error)
    var errorDescription: String? {
        switch self {
        case .noPieces: "Couldn't identify any pieces in this image."
        case .anthropic(let e): e.localizedDescription
        }
    }
}

struct RecreateService {
    let client = AnthropicClient()

    func analyze(
        image: UIImage,
        closet: [Item],
        references: [ReferenceLook]
    ) async throws -> RecreateResult {

        let snapshotIds = Set(closet.map(\.id))

        var blocks: [AnthropicClient.ContentBlock] = []
        blocks.append(.text("REFERENCE OUTFIT (parse pieces and match against the closet):"))
        blocks.append(.image(image))

        blocks.append(.text("\nCLOSET INVENTORY (match against these — use only these item IDs):"))
        for item in closet {
            if let img = ImageStore.load(item.thumbnailPath) { blocks.append(.image(img)) }
            blocks.append(.text("ID: \(item.id.uuidString) — \(item.name) [\(item.category.rawValue), colors: \(item.colors.joined(separator: ","))]"))
        }
        if !references.isEmpty {
            blocks.append(.text("\nThe user's general taste anchor (for context only):"))
            for r in references.prefix(5) {
                if let img = ImageStore.load(r.thumbnailPath) { blocks.append(.image(img)) }
            }
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "parsedPieces": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "description": ["type": "string"],
                            "category": ["type": "string", "enum": ItemCategory.allCases.map(\.rawValue)],
                            "colors": ["type": "array", "items": ["type": "string"]],
                            "formality": ["type": "string", "enum": Formality.allCases.map(\.rawValue)],
                        ],
                        "required": ["description", "category", "colors"],
                    ],
                ],
                "matches": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "pieceIndex": ["type": "integer"],
                            "status": ["type": "string", "enum": ["matched", "missing"]],
                            "itemId": ["type": "string"],
                            "confidence": ["type": "string", "enum": ["veryClose", "close", "loose"]],
                            "note": ["type": "string"],
                        ],
                        "required": ["pieceIndex", "status"],
                    ],
                ],
            ],
            "required": ["parsedPieces", "matches"],
        ]

        let system = """
        Parse the reference outfit into its primary pieces (top, bottom, outerwear, shoes, hero accessory — max 5).
        For each piece, either match to an itemId from the CLOSET INVENTORY or mark missing.
        Use ONLY itemIds from the inventory. Never invent.
        Match confidence: veryClose | close | loose.
        Include a short note explaining the match or what's missing.
        """

        let input: [String: Any]
        do {
            input = try await client.callTool(
                system: system,
                toolName: "parse_and_match",
                toolDescription: "Parse the outfit and match each piece against the closet",
                toolInputSchema: schema,
                userBlocks: blocks
            )
        } catch {
            throw RecreateError.anthropic(error)
        }

        guard
            let piecesRaw = input["parsedPieces"] as? [[String: Any]],
            let matchesRaw = input["matches"] as? [[String: Any]]
        else { throw RecreateError.noPieces }

        let pieces: [ParsedPiece] = piecesRaw.compactMap { p in
            guard let desc = p["description"] as? String,
                  let catStr = p["category"] as? String,
                  let cat = ItemCategory(rawValue: catStr),
                  let colors = p["colors"] as? [String] else { return nil }
            let formality = (p["formality"] as? String).flatMap(Formality.init(rawValue:))
            return ParsedPiece(description: desc, category: cat, colors: colors, formality: formality)
        }
        guard !pieces.isEmpty else { throw RecreateError.noPieces }

        let matches: [PieceMatch] = matchesRaw.compactMap { m in
            guard let idx = m["pieceIndex"] as? Int,
                  let statusStr = m["status"] as? String,
                  let status = MatchStatus(rawValue: statusStr) else { return nil }
            var matchedId: UUID? = nil
            if status == .matched, let idStr = m["itemId"] as? String, let id = UUID(uuidString: idStr), snapshotIds.contains(id) {
                matchedId = id
            }
            // If it was supposed to be matched but invalid, downgrade to missing
            let effectiveStatus: MatchStatus = (status == .matched && matchedId == nil) ? .missing : status
            let confidence = (m["confidence"] as? String).flatMap(MatchConfidence.init(rawValue:))
            return PieceMatch(pieceIndex: idx, status: effectiveStatus, matchedItemId: matchedId, confidence: confidence, note: m["note"] as? String, wantedPieceId: nil)
        }

        return RecreateResult(parsedPieces: pieces, matches: matches)
    }
}
