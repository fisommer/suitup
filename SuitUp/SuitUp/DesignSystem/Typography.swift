import SwiftUI
import UIKit

/// SuitUp typography tokens.
///
/// Two font families:
///   - Fraunces (variable, opsz axis) — display + tab titles + item hero names
///   - Inter (variable) — body, UI, captions, labels
///
/// Always use these `.su…` modifiers, never call `.font(.title)` / `.font(.headline)` directly.
///
/// Spec: `docs/superpowers/specs/2026-06-30-ui-overhaul-design.md`

extension Font {
    static let suDisplay        = Font.custom("Fraunces", size: 44).weight(.medium)
    static let suTitle          = Font.custom("Fraunces", size: 30).weight(.medium)
    static let suSectionTitle   = Font.custom("Fraunces", size: 22).weight(.medium)

    static let suHeadline       = Font.custom("Inter Variable", size: 17).weight(.semibold)
    static let suBody           = Font.custom("Inter Variable", size: 15)
    static let suCaption        = Font.custom("Inter Variable", size: 13)
    static let suLabel          = Font.custom("Inter Variable", size: 11).weight(.semibold)
}

/// View modifiers that bundle the right font + tracking + line spacing per token.
/// Prefer these over `.font(.suTitle)` directly for headings — they apply tracking.
extension View {
    func suDisplay() -> some View {
        font(.suDisplay)
            .tracking(-0.88)             // -2% of 44
            .lineSpacing(44 * 0.05)
    }
    func suTitle() -> some View {
        font(.suTitle)
            .tracking(-0.45)             // -1.5% of 30
            .lineSpacing(30 * 0.15)
    }
    func suSectionTitle() -> some View {
        font(.suSectionTitle)
            .tracking(-0.22)
            .lineSpacing(22 * 0.25)
    }
    func suHeadline() -> some View {
        font(.suHeadline)
            .tracking(-0.17)             // -1% of 17
    }
    func suBody() -> some View {
        font(.suBody)
            .lineSpacing(15 * 0.5)       // line-height 1.5
    }
    func suCaption() -> some View {
        font(.suCaption)
            .lineSpacing(13 * 0.4)
    }
    /// Uppercase label with +8% tracking.
    func suLabel() -> some View {
        font(.suLabel)
            .tracking(11 * 0.08)
            .textCase(.uppercase)
    }
}

// MARK: - Font registration

/// Register bundled custom fonts with the iOS font registry at app start.
///
/// Must be called before any SwiftUI view tries to use `Font.custom("Fraunces", ...)`
/// or `Font.custom("Inter", ...)`. Idempotent — safe to call multiple times.
enum SUFonts {
    static func register() {
        register(filename: "Fraunces-Variable", ext: "ttf")
        register(filename: "Inter-Variable", ext: "ttf")
    }

    private static func register(filename: String, ext: String) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: ext) else {
            print("[SUFonts] Missing font file: \(filename).\(ext)")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already-registered is a non-fatal error code (105).
            if let cfErr = error?.takeRetainedValue() as Error?,
               (cfErr as NSError).code != 105 {
                print("[SUFonts] Failed to register \(filename): \(cfErr)")
            }
        }
    }
}
