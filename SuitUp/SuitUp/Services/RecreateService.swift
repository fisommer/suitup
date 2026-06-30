import Foundation
import UIKit

struct RecreateResult {
    let parsedPieces: [ParsedPiece]
    let matches: [PieceMatch]
    /// AI-suggested short outfit name (~3-5 words). User can edit before saving.
    let suggestedName: String?
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
                "suggestedName": [
                    "type": "string",
                    "description": "Short, evocative name for the outfit (3-5 words, no quotes). Examples: 'Linen Riviera fit', 'Tailored weekend uniform', 'Cream summer drift'.",
                ],
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
                            "itemIds": [
                                "type": "array",
                                "items": ["type": "string"],
                                "description": "All closet itemIds that match this piece, ordered best→worst. Empty if missing.",
                            ],
                            "confidence": ["type": "string", "enum": ["veryClose", "close", "loose"]],
                            "note": ["type": "string"],
                        ],
                        "required": ["pieceIndex", "status"],
                    ],
                ],
            ],
            "required": ["suggestedName", "parsedPieces", "matches"],
        ]

        let system = """
        Parse the reference outfit into its primary pieces (top, bottom, outerwear, shoes, hero accessory — max 5).
        For each piece, list ALL closet itemIds that could match it, ordered best→worst (typically 1-3). Mark missing only if nothing in the closet works.
        Use ONLY itemIds from the inventory. Never invent.
        Match confidence reflects the best match: veryClose | close | loose.
        Include a short note explaining the matches or what's missing.
        Also suggest a short, evocative outfit name (3-5 words, no quotes) that captures the look's character.
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

            // Accept both new `itemIds` array and legacy `itemId` string from the model.
            var ids: [UUID] = []
            if let arr = m["itemIds"] as? [String] {
                ids = arr.compactMap(UUID.init(uuidString:)).filter { snapshotIds.contains($0) }
            } else if let single = m["itemId"] as? String, let id = UUID(uuidString: single), snapshotIds.contains(id) {
                ids = [id]
            }

            // If supposed to be matched but no valid IDs survived, downgrade to missing.
            let effectiveStatus: MatchStatus = (status == .matched && ids.isEmpty) ? .missing : status
            let confidence = (m["confidence"] as? String).flatMap(MatchConfidence.init(rawValue:))
            return PieceMatch(
                pieceIndex: idx,
                status: effectiveStatus,
                matchedItemIds: ids,
                confidence: confidence,
                note: m["note"] as? String,
                wantedPieceId: nil
            )
        }

        let suggestedName = (input["suggestedName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let cleanName = suggestedName.flatMap { $0.isEmpty ? nil : $0 }

        return RecreateResult(parsedPieces: pieces, matches: matches, suggestedName: cleanName)
    }
}
