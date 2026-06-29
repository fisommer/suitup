import Foundation
import SwiftData

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case top, bottom, outerwear, footwear, accessory, fullBody
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .outerwear: return "Outerwear"
        case .footwear: return "Footwear"
        case .accessory: return "Accessory"
        case .fullBody: return "Full body"
        }
    }
}

enum Formality: String, Codable, CaseIterable {
    case casual, smartCasual, formal, sportswear
}

enum Season: String, Codable, CaseIterable {
    case spring, summer, autumn, winter
}

enum Fit: String, Codable, CaseIterable {
    case loose, regular, slim, tailored
}

enum ItemSource: String, Codable {
    case photo, urlCrawl
}

@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var imagePath: String
    var originalImagePath: String
    var thumbnailPath: String
    var additionalImagePaths: [String]
    var sourceRaw: String
    var sourceUrl: String?
    var name: String
    var categoryRaw: String
    var subcategory: String
    var colors: [String]
    var formalityRaw: String
    var seasonsRaw: [String]
    var pattern: String?
    var material: String?
    var brand: String?
    var size: String?
    var fitRaw: String?
    var occasionTags: [String]
    var purchaseDate: Date?
    var price: Decimal?
    var purchasedFrom: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        imagePath: String,
        originalImagePath: String,
        thumbnailPath: String,
        additionalImagePaths: [String] = [],
        source: ItemSource,
        sourceUrl: String? = nil,
        name: String,
        category: ItemCategory,
        subcategory: String,
        colors: [String],
        formality: Formality,
        seasons: [Season],
        pattern: String? = nil,
        material: String? = nil,
        brand: String? = nil,
        size: String? = nil,
        fit: Fit? = nil,
        occasionTags: [String] = [],
        purchaseDate: Date? = nil,
        price: Decimal? = nil,
        purchasedFrom: String? = nil,
        notes: String? = nil
    ) {
        let now = Date()
        self.id = id
        self.imagePath = imagePath
        self.originalImagePath = originalImagePath
        self.thumbnailPath = thumbnailPath
        self.additionalImagePaths = additionalImagePaths
        self.sourceRaw = source.rawValue
        self.sourceUrl = sourceUrl
        self.name = name
        self.categoryRaw = category.rawValue
        self.subcategory = subcategory
        self.colors = colors
        self.formalityRaw = formality.rawValue
        self.seasonsRaw = seasons.map(\.rawValue)
        self.pattern = pattern
        self.material = material
        self.brand = brand
        self.size = size
        self.fitRaw = fit?.rawValue
        self.occasionTags = occasionTags
        self.purchaseDate = purchaseDate
        self.price = price
        self.purchasedFrom = purchasedFrom
        self.notes = notes
        self.createdAt = now
        self.updatedAt = now
    }

    var category: ItemCategory { ItemCategory(rawValue: categoryRaw) ?? .top }
    var formality: Formality { Formality(rawValue: formalityRaw) ?? .casual }
    var seasons: [Season] { seasonsRaw.compactMap(Season.init(rawValue:)) }
    var source: ItemSource { ItemSource(rawValue: sourceRaw) ?? .photo }
    var fit: Fit? { fitRaw.flatMap(Fit.init(rawValue:)) }
}
