import Foundation
import UIKit

struct StyleSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let itemIds: [UUID]
    let rationale: String
}

enum StylingError: Error, LocalizedError {
    case noKey
    case noValidSuggestions
    case anthropic(Error)

    var errorDescription: String? {
        switch self {
        case .noKey: "Anthropic API key not set. Add it in Settings."
        case .noValidSuggestions: "Couldn't produce valid suggestions. Try refreshing or adjusting your closet."
        case .anthropic(let e): e.localizedDescription
        }
    }
}

struct StylingService {
    let client = AnthropicClient()

    /// Returns up to 3 validated suggestions referencing real closet items.
    func suggestOutfits(
        for selected: Item,
        closet: [Item],
        savedOutfits: [Outfit],
        references: [ReferenceLook],
        previouslySuggested: [[UUID]] = []
    ) async throws -> [StyleSuggestion] {

        guard KeychainStore.hasKey else { throw StylingError.noKey }

        let compatible = filterCompatible(closet: closet, for: selected)
        let cap = 30
        let closetSnapshot = Array(compatible.prefix(cap))
        let snapshotIds = Set(closetSnapshot.map(\.id))

        let savedWithSelected = Array(savedOutfits
            .filter { $0.itemIds.contains(selected.id) }
            .prefix(5))
        let refsToSend = Array(references.prefix(10))

        // Build the user content blocks
        var blocks: [AnthropicClient.ContentBlock] = []
        blocks.append(.text("SELECTED PIECE (must appear in every outfit you suggest):"))
        if let img = ImageStore.load(selected.imagePath) {
            blocks.append(.image(img))
        }
        blocks.append(.text("""
            ID: \(selected.id.uuidString)
            Name: \(selected.name)
            Category: \(selected.category.rawValue)
            Colors: \(selected.colors.joined(separator: ", "))
            Formality: \(selected.formality.rawValue)
            """))

        if !refsToSend.isEmpty {
            blocks.append(.text("\nREFERENCE LOOKS (the user's aesthetic — match this taste):"))
            for ref in refsToSend {
                if let img = ImageStore.load(ref.thumbnailPath) {
                    blocks.append(.image(img))
                }
            }
        }

        blocks.append(.text("\nCLOSET INVENTORY (use ONLY these item IDs — never invent items):"))
        for item in closetSnapshot {
            if let img = ImageStore.load(item.thumbnailPath) {
                blocks.append(.image(img))
            }
            blocks.append(.text("ID: \(item.id.uuidString) — \(item.name) [\(item.category.rawValue), colors: \(item.colors.joined(separator: ", ")), formality: \(item.formality.rawValue)]"))
        }

        if !savedWithSelected.isEmpty {
            blocks.append(.text("\nThe user has previously assembled these outfits including the selected piece — they reflect the user's existing combinations:"))
            for o in savedWithSelected {
                if let img = ImageStore.load(o.coverImagePath) {
                    blocks.append(.image(img))
                }
            }
        }

        if !previouslySuggested.isEmpty {
            let avoidLines = previouslySuggested.map { ids in
                ids.map(\.uuidString).joined(separator: ", ")
            }.joined(separator: "\n")
            blocks.append(.text("\nAVOID repeating these specific item-set combinations:\n\(avoidLines)"))
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "outfits": [
                    "type": "array",
                    "minItems": 3,
                    "maxItems": 3,
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string", "description": "Short evocative outfit name"],
                            "itemIds": [
                                "type": "array",
                                "items": ["type": "string"],
                                "description": "3–5 item IDs from the closet inventory, including the selected piece",
                            ],
                            "rationale": ["type": "string", "description": "1–2 sentences explaining why this outfit works"],
                        ],
                        "required": ["name", "itemIds", "rationale"],
                    ],
                ],
            ],
            "required": ["outfits"],
        ]

        let system = """
        You are a personal stylist. Your job: suggest 3 outfits that include the SELECTED PIECE.

        Rules:
        - Each outfit MUST include the selected piece's exact ID.
        - Use ONLY itemIds from the provided CLOSET INVENTORY — never invent items.
        - Each outfit must include 3–5 items total (including the selected piece).
        - Each outfit must be distinct from the others.
        - Lean toward the aesthetic of the REFERENCE LOOKS.
        - Provide a 1–2 sentence rationale per outfit explaining the styling logic.
        """

        let input: [String: Any]
        do {
            input = try await client.callTool(
                system: system,
                toolName: "suggest_outfits",
                toolDescription: "Return 3 outfit suggestions",
                toolInputSchema: schema,
                userBlocks: blocks
            )
        } catch {
            throw StylingError.anthropic(error)
        }

        guard let outfitsRaw = input["outfits"] as? [[String: Any]] else {
            throw StylingError.noValidSuggestions
        }

        var validSuggestions: [StyleSuggestion] = []
        for raw in outfitsRaw {
            guard
                let name = raw["name"] as? String,
                let idStrings = raw["itemIds"] as? [String],
                let rationale = raw["rationale"] as? String
            else { continue }
            let ids = idStrings.compactMap(UUID.init(uuidString:))
            // Validate: every id must be in the snapshot, must include selected, count in 3–5
            let allValid = ids.allSatisfy { snapshotIds.contains($0) || $0 == selected.id }
            let includesSelected = ids.contains(selected.id)
            if allValid && includesSelected && ids.count >= 3 && ids.count <= 5 {
                validSuggestions.append(StyleSuggestion(name: name, itemIds: ids, rationale: rationale))
            } else {
                print("[Styling] Rejected suggestion '\(name)': allValid=\(allValid), includesSelected=\(includesSelected), count=\(ids.count)")
            }
        }

        guard !validSuggestions.isEmpty else {
            throw StylingError.noValidSuggestions
        }
        return validSuggestions
    }

    /// Compatible items = same closet minus the selected piece, minus same-slot conflicts.
    private func filterCompatible(closet: [Item], for selected: Item) -> [Item] {
        let excludeCategory: ItemCategory?
        switch selected.category {
        case .top, .bottom, .footwear, .fullBody:
            excludeCategory = selected.category
        case .outerwear, .accessory:
            excludeCategory = nil  // allow layering outerwear, allow many accessories
        }
        return closet
            .filter { item in
                if item.id == selected.id { return false }
                if let exclude = excludeCategory, item.category == exclude { return false }
                return true
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
