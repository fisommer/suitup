import Foundation
import SwiftData

/// Export + wipe helpers for the user's SuitUp data.
///
/// SwiftData `@Model` classes aren't `Codable` directly — we walk each model type
/// and build a dictionary representation manually. Export is JSON-only:
/// image *paths* are included but image bytes are not (keeps the export small).
enum DataPortability {

    // MARK: - Export

    /// Exports every SwiftData entity to a JSON file in the app's temp directory.
    /// Returns the file URL for sharing via UIActivityViewController.
    @MainActor
    static func exportAll(context: ModelContext) throws -> URL {
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "items": try fetchAll(Item.self, context: context).map(itemDict),
            "outfits": try fetchAll(Outfit.self, context: context).map(outfitDict),
            "references": try fetchAll(ReferenceLook.self, context: context).map(referenceDict),
            "recreateAttempts": try fetchAll(RecreateAttempt.self, context: context).map(recreateDict),
            "wantedPieces": try fetchAll(WantedPiece.self, context: context).map(wantedDict),
            "wearEvents": try fetchAll(WearEvent.self, context: context).map(wearEventDict),
            "stylingRequests": try fetchAll(StylingRequest.self, context: context).map(stylingDict),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let filename = "suitup-export-\(filenameTimestamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Wipe

    /// Deletes every SwiftData entity and every file in ImageStore's folders.
    /// Preserves: Keychain (API key), App Group inbox.
    @MainActor
    static func clearAll(context: ModelContext) throws {
        // 1. SwiftData entities — delete each by type.
        try deleteAll(Item.self, context: context)
        try deleteAll(Outfit.self, context: context)
        try deleteAll(ReferenceLook.self, context: context)
        try deleteAll(RecreateAttempt.self, context: context)
        try deleteAll(WantedPiece.self, context: context)
        try deleteAll(WearEvent.self, context: context)
        try deleteAll(StylingRequest.self, context: context)
        try context.save()

        // 2. Image folders — empty each.
        for folder in [ImageStoreFolder.items, .references, .outfits, .recreate] {
            let dir = ImageStore.folderURL(folder)
            let contents = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Internals

    private static func fetchAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        let all = try fetchAll(type, context: context)
        for entity in all {
            context.delete(entity)
        }
    }

    private static func filenameTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    // MARK: - Per-model dict builders

    private static func itemDict(_ i: Item) -> [String: Any] {
        [
            "id": i.id.uuidString,
            "name": i.name,
            "category": i.categoryRaw,
            "subcategory": i.subcategory,
            "colors": i.colors,
            "formality": i.formalityRaw,
            "seasons": i.seasonsRaw,
            "fit": i.fitRaw as Any,
            "pattern": i.pattern as Any,
            "material": i.material as Any,
            "brand": i.brand as Any,
            "size": i.size as Any,
            "occasionTags": i.occasionTags,
            "purchaseDate": i.purchaseDate.map(ISO8601DateFormatter().string(from:)) as Any,
            "price": i.price.map { NSDecimalNumber(decimal: $0).stringValue } as Any,
            "purchasedFrom": i.purchasedFrom as Any,
            "notes": i.notes as Any,
            "source": i.sourceRaw,
            "sourceUrl": i.sourceUrl as Any,
            "imagePath": i.imagePath,
            "originalImagePath": i.originalImagePath,
            "thumbnailPath": i.thumbnailPath,
            "additionalImagePaths": i.additionalImagePaths,
            "createdAt": ISO8601DateFormatter().string(from: i.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: i.updatedAt),
        ]
    }

    private static func outfitDict(_ o: Outfit) -> [String: Any] {
        [
            "id": o.id.uuidString,
            "name": o.name,
            "itemIds": o.itemIds.map(\.uuidString),
            "coverImagePath": o.coverImagePath,
            "source": o.sourceRaw,
            "rationale": o.rationale as Any,
            "notes": o.notes as Any,
            "createdAt": ISO8601DateFormatter().string(from: o.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: o.updatedAt),
        ]
    }

    private static func referenceDict(_ r: ReferenceLook) -> [String: Any] {
        [
            "id": r.id.uuidString,
            "imagePath": r.imagePath,
            "thumbnailPath": r.thumbnailPath,
            "source": r.sourceRaw,
            "sourceUrl": r.sourceUrl as Any,
            "note": r.note as Any,
            "createdAt": ISO8601DateFormatter().string(from: r.createdAt),
        ]
    }

    private static func recreateDict(_ a: RecreateAttempt) -> [String: Any] {
        [
            "id": a.id.uuidString,
            "name": a.name as Any,
            "sourceImagePath": a.sourceImagePath,
            "sourceUrl": a.sourceUrl as Any,
            "parsedPieces": (try? JSONSerialization.jsonObject(with: a.parsedPiecesJSON)) ?? [],
            "matches": (try? JSONSerialization.jsonObject(with: a.matchesJSON)) ?? [],
            "recreatableCount": a.recreatableCount,
            "totalPieceCount": a.totalPieceCount,
            "linkedReferenceLookId": a.linkedReferenceLookId?.uuidString as Any,
            "savedOutfitId": a.savedOutfitId?.uuidString as Any,
            "createdAt": ISO8601DateFormatter().string(from: a.createdAt),
        ]
    }

    private static func wantedDict(_ w: WantedPiece) -> [String: Any] {
        [
            "id": w.id.uuidString,
            "pieceDescription": w.pieceDescription,
            "category": w.categoryRaw,
            "colors": w.colors,
            "sourceRecreateAttemptId": w.sourceRecreateAttemptId.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: w.createdAt),
        ]
    }

    private static func wearEventDict(_ w: WearEvent) -> [String: Any] {
        [
            "id": w.id.uuidString,
            "itemId": w.itemId?.uuidString as Any,
            "outfitId": w.outfitId?.uuidString as Any,
            "timestamp": ISO8601DateFormatter().string(from: w.timestamp),
        ]
    }

    private static func stylingDict(_ s: StylingRequest) -> [String: Any] {
        [
            "id": s.id.uuidString,
            "itemId": s.itemId.uuidString,
            "contextOccasion": s.contextOccasion as Any,
            "contextWeather": s.contextWeather as Any,
            "closetSnapshotIds": s.closetSnapshotIds.map(\.uuidString),
            "suggestions": (try? JSONSerialization.jsonObject(with: s.suggestionsJSON)) ?? [],
            "modelCostUSD": s.modelCostUSD as Any,
            "timestamp": ISO8601DateFormatter().string(from: s.timestamp),
        ]
    }
}
