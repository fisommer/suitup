import Foundation

/// App Group helpers for shared file storage between SuitUp and SuitUpShareExtension.
///
/// The extension is sandboxed in its own process and cannot touch SwiftData directly.
/// Pattern: extension writes a small JSON manifest + (optionally) an image file to the
/// inbox dir; main app drains the inbox on launch/foreground.
///
/// Target membership: this file must belong to BOTH the SuitUp target AND the
/// SuitUpShareExtension target. Check the file inspector → Target Membership.
enum SharedContainer {
    static let appGroupID = "group.dev.fisommer.SuitUp.shared"

    static func url() -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group container missing — check entitlements for \(appGroupID)")
        }
        return url
    }

    static func inboxURL() -> URL {
        let u = url().appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}
