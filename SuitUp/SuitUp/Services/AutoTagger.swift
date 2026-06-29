import UIKit

struct AutoTagResult {
    let name: String
    let category: ItemCategory
    let subcategory: String
    let colors: [String]
    let formality: Formality
    let seasons: [Season]
    let pattern: String?
    let material: String?
    let fit: Fit?
    let occasionTags: [String]
    let isNotClothing: Bool
}

struct AutoTagger {
    let client = AnthropicClient()

    private let system = """
    You are tagging a single clothing item from a photograph. Be precise. \
    If the image is not a clothing item, set category="not-clothing". \
    Mark material as your best guess. Leave fields you cannot determine \
    confidently as omitted.
    """

    private let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": ["type": "string", "description": "Short descriptive name, e.g. 'Beige Linen Shirt'"],
            "category": ["type": "string", "enum": ItemCategory.allCases.map(\.rawValue) + ["not-clothing"]],
            "subcategory": ["type": "string", "description": "T-shirt, Shirt, Chinos, etc."],
            "colors": ["type": "array", "items": ["type": "string"]],
            "formality": ["type": "string", "enum": Formality.allCases.map(\.rawValue)],
            "seasons": [
                "type": "array",
                "items": ["type": "string", "enum": Season.allCases.map(\.rawValue)],
            ],
            "pattern": ["type": "string", "description": "solid, striped, plaid, floral, etc."],
            "material": ["type": "string", "description": "best guess, e.g. cotton, linen, wool"],
            "fit": ["type": "string", "enum": Fit.allCases.map(\.rawValue)],
            "occasionTags": ["type": "array", "items": ["type": "string"], "description": "work, casual, gym, going-out, etc."],
        ],
        "required": ["name", "category"],
    ]

    func tag(image: UIImage) async throws -> AutoTagResult {
        let input = try await client.callTool(
            system: system,
            toolName: "tag_item",
            toolDescription: "Report the identified clothing tags",
            toolInputSchema: schema,
            userBlocks: [.image(image), .text("Identify and tag this clothing item.")]
        )

        let categoryStr = input["category"] as? String ?? "top"
        let isNotClothing = categoryStr == "not-clothing"
        let category = ItemCategory(rawValue: categoryStr) ?? .top

        return AutoTagResult(
            name: input["name"] as? String ?? "Untitled",
            category: category,
            subcategory: input["subcategory"] as? String ?? "",
            colors: input["colors"] as? [String] ?? [],
            formality: Formality(rawValue: input["formality"] as? String ?? "casual") ?? .casual,
            seasons: (input["seasons"] as? [String] ?? []).compactMap(Season.init(rawValue:)),
            pattern: input["pattern"] as? String,
            material: input["material"] as? String,
            fit: (input["fit"] as? String).flatMap(Fit.init(rawValue:)),
            occasionTags: input["occasionTags"] as? [String] ?? [],
            isNotClothing: isNotClothing
        )
    }
}
