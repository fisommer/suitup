import SwiftUI
import UIKit

struct ItemConfirmDraft {
    var originalImage: UIImage
    var bgRemovedImage: UIImage
    var useBackgroundRemoved: Bool = true
    var bgRemovalSucceeded: Bool = true   // false → toggle should default off + note shown
    var name: String = ""
    var category: ItemCategory = .top
    var subcategory: String = ""
    var colors: [String] = []
    var formality: Formality = .casual
    var seasons: Set<Season> = []
    var pattern: String = ""
    var material: String = ""
    var brand: String = ""
    var size: String = ""
    var fit: Fit? = nil
    var occasionTags: [String] = []
    var purchaseDate: Date? = nil
    var price: Decimal? = nil
    var purchasedFrom: String? = nil
    var notes: String = ""
    var source: ItemSource = .photo
    var sourceUrl: String? = nil
    var additionalImages: [UIImage] = []

    var materialIsGuess: Bool = true

    /// Non-fatal warnings from the URL crawler (e.g. "couldn't resolve color variant").
    /// Surfaced as an info banner at the top of the confirm sheet.
    var crawlWarnings: [String] = []
}
