#if DEBUG
import Foundation
import SwiftData
import UIKit

enum SeedData {
    /// Populate ~12 sample items across all categories so the closet UI can be
    /// developed without needing the photo-capture flow yet. Idempotent: skips
    /// if any items already exist.
    static func seed(modelContext: ModelContext) {
        let existing = try? modelContext.fetch(FetchDescriptor<Item>())
        guard (existing ?? []).isEmpty else { return }

        for sample in samples {
            let id = UUID()
            let image = placeholderImage(color: sample.color, label: sample.label, size: CGSize(width: 400, height: 500))
            let thumb = placeholderImage(color: sample.color, label: sample.label, size: CGSize(width: 220, height: 280))

            let imagePath = (try? ImageStore.save(image, folder: .items, name: "\(id)")) ?? ""
            let thumbPath = (try? ImageStore.save(thumb, folder: .items, name: "\(id)-thumb")) ?? ""

            let item = Item(
                id: id,
                imagePath: imagePath,
                originalImagePath: imagePath,
                thumbnailPath: thumbPath,
                source: .photo,
                name: sample.name,
                category: sample.category,
                subcategory: sample.subcategory,
                colors: sample.colors,
                formality: sample.formality,
                seasons: sample.seasons,
                pattern: sample.pattern,
                material: sample.material,
                brand: sample.brand
            )
            modelContext.insert(item)
        }
        try? modelContext.save()
    }

    static func wipe(modelContext: ModelContext, items: [Item]) {
        for item in items {
            ImageStore.delete(item.imagePath)
            ImageStore.delete(item.thumbnailPath)
            ImageStore.delete(item.originalImagePath)
            item.additionalImagePaths.forEach { ImageStore.delete($0) }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    // MARK: - Sample data

    private struct Sample {
        let name: String
        let category: ItemCategory
        let subcategory: String
        let colors: [String]
        let formality: Formality
        let seasons: [Season]
        let pattern: String?
        let material: String?
        let brand: String?
        let color: UIColor
        let label: String
    }

    private static let samples: [Sample] = [
        // Outerwear
        Sample(name: "Olive utility jacket", category: .outerwear, subcategory: "Jacket", colors: ["olive"],
               formality: .casual, seasons: [.spring, .autumn], pattern: "solid", material: "cotton", brand: "Carhartt",
               color: UIColor(red: 0.45, green: 0.50, blue: 0.30, alpha: 1), label: "Jacket"),
        Sample(name: "Black wool coat", category: .outerwear, subcategory: "Coat", colors: ["black"],
               formality: .formal, seasons: [.winter], pattern: "solid", material: "wool", brand: "COS",
               color: UIColor(white: 0.15, alpha: 1), label: "Coat"),

        // Tops
        Sample(name: "White crew tee", category: .top, subcategory: "T-shirt", colors: ["white"],
               formality: .casual, seasons: [.spring, .summer], pattern: "solid", material: "cotton", brand: "Uniqlo",
               color: UIColor(white: 0.95, alpha: 1), label: "Tee"),
        Sample(name: "Beige linen shirt", category: .top, subcategory: "Shirt", colors: ["beige"],
               formality: .smartCasual, seasons: [.spring, .summer], pattern: "solid", material: "linen", brand: "COS",
               color: UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 1), label: "Shirt"),
        Sample(name: "Navy oxford shirt", category: .top, subcategory: "Shirt", colors: ["navy"],
               formality: .smartCasual, seasons: [.autumn, .winter, .spring], pattern: "solid", material: "cotton", brand: nil,
               color: UIColor(red: 0.13, green: 0.20, blue: 0.40, alpha: 1), label: "Oxford"),
        Sample(name: "Grey marl hoodie", category: .top, subcategory: "Hoodie", colors: ["grey"],
               formality: .casual, seasons: [.autumn, .winter], pattern: "solid", material: "cotton", brand: "Uniqlo",
               color: UIColor(white: 0.55, alpha: 1), label: "Hoodie"),

        // Bottoms
        Sample(name: "Black slim jeans", category: .bottom, subcategory: "Jeans", colors: ["black"],
               formality: .casual, seasons: [.autumn, .winter, .spring], pattern: "solid", material: "denim", brand: "Levi's",
               color: UIColor(white: 0.12, alpha: 1), label: "Jeans"),
        Sample(name: "Cream pleated trousers", category: .bottom, subcategory: "Trousers", colors: ["cream"],
               formality: .smartCasual, seasons: [.spring, .summer], pattern: "solid", material: "linen", brand: "COS",
               color: UIColor(red: 0.94, green: 0.90, blue: 0.78, alpha: 1), label: "Trousers"),
        Sample(name: "Khaki chinos", category: .bottom, subcategory: "Chinos", colors: ["khaki"],
               formality: .smartCasual, seasons: [.spring, .summer, .autumn], pattern: "solid", material: "cotton", brand: nil,
               color: UIColor(red: 0.72, green: 0.65, blue: 0.45, alpha: 1), label: "Chinos"),

        // Footwear
        Sample(name: "White Veja sneakers", category: .footwear, subcategory: "Sneakers", colors: ["white"],
               formality: .casual, seasons: [.spring, .summer, .autumn], pattern: "solid", material: "leather", brand: "Veja",
               color: UIColor(white: 0.92, alpha: 1), label: "Sneakers"),
        Sample(name: "Tan leather loafers", category: .footwear, subcategory: "Loafers", colors: ["tan"],
               formality: .smartCasual, seasons: [.spring, .summer, .autumn], pattern: "solid", material: "leather", brand: nil,
               color: UIColor(red: 0.70, green: 0.55, blue: 0.35, alpha: 1), label: "Loafers"),

        // Accessory
        Sample(name: "Brown leather belt", category: .accessory, subcategory: "Belt", colors: ["brown"],
               formality: .smartCasual, seasons: [.spring, .summer, .autumn, .winter], pattern: "solid", material: "leather", brand: nil,
               color: UIColor(red: 0.45, green: 0.30, blue: 0.20, alpha: 1), label: "Belt"),
    ]

    private static func placeholderImage(color: UIColor, label: String, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Label
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width * 0.10, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                .paragraphStyle: para,
            ]
            let attributed = NSAttributedString(string: label, attributes: attributes)
            let textHeight = attributed.size().height
            let textRect = CGRect(
                x: 0,
                y: (size.height - textHeight) / 2,
                width: size.width,
                height: textHeight
            )
            attributed.draw(in: textRect)
        }
    }
}
#endif
