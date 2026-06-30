import SwiftUI
import SwiftData

@main
struct SuitUpApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Outfit.self,
            ReferenceLook.self,
            RecreateAttempt.self,
            WantedPiece.self,
            WearEvent.self,
            StylingRequest.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingInbox: [InboxItem] = []
    @State private var currentInbox: InboxItem?

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task { await processInbox() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await processInbox() }
                    }
                }
                .onChange(of: pendingInbox) { _, _ in
                    presentNextIfNeeded()
                }
                .sheet(item: $currentInbox, onDismiss: {
                    presentNextIfNeeded()
                }) { item in
                    InboxRouterView(item: item)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Pops the next queued inbox item into `currentInbox` if no sheet is currently up.
    @MainActor
    private func presentNextIfNeeded() {
        guard currentInbox == nil, !pendingInbox.isEmpty else { return }
        currentInbox = pendingInbox.removeFirst()
    }

    /// Scans the App Group inbox for `*.json` manifests, parses each into an `InboxItem`,
    /// and deletes the manifest. The companion image file (if any) is NOT deleted yet —
    /// `InboxRouterView` is responsible for cleaning that up after the receiving flow
    /// has consumed (or cancelled) it.
    @MainActor
    private func processInbox() async {
        let inboxDir = SharedContainer.inboxURL()
        let urls = (try? FileManager.default.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: nil)) ?? []
        let manifests = urls.filter { $0.pathExtension == "json" }
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

        var newItems: [InboxItem] = []
        for manifest in manifests {
            defer { try? FileManager.default.removeItem(at: manifest) }
            guard
                let data = try? Data(contentsOf: manifest),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let action = obj["action"] as? String
            else { continue }

            let item = InboxItem(
                id: UUID(),
                action: action,
                imageFileName: obj["imagePath"] as? String,
                url: obj["url"] as? String
            )
            newItems.append(item)
        }
        if !newItems.isEmpty {
            pendingInbox.append(contentsOf: newItems)
            presentNextIfNeeded()
        }
    }
}

struct InboxItem: Identifiable, Equatable {
    let id: UUID
    let action: String
    /// Filename inside the App Group inbox dir (e.g. "abc123.img"). Not a full path.
    let imageFileName: String?
    let url: String?
}

private extension URL {
    var creationDate: Date? {
        (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
}
