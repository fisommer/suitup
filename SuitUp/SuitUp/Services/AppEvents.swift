import Foundation
import Combine

/// Lightweight pub-sub for cross-screen events (saved-item flash, etc.).
@MainActor
final class AppEvents: ObservableObject {
    static let shared = AppEvents()
    private init() {}

    @Published var lastSavedItemId: UUID?
    @Published var lastSavedItemName: String?
    @Published var showSavedToast: Bool = false

    /// Call after a new item is successfully saved.
    func didSaveItem(id: UUID, name: String) {
        lastSavedItemId = id
        lastSavedItemName = name
        showSavedToast = true
        // Auto-clear the toast flag after a moment.
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { showSavedToast = false }
        }
        // Auto-clear the highlight after a couple of seconds.
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run {
                if lastSavedItemId == id { lastSavedItemId = nil }
            }
        }
    }
}
