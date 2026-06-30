import SwiftUI
import UIKit

/// SuitUp's design system foundation.
///
/// Every visual choice in the app — color, spacing, radius, elevation, motion —
/// comes from this file. Screens should never use literal numbers; they should
/// use these tokens.
///
/// Color values are dynamic providers so the app supports light + dark mode
/// without semantic-color guesswork from iOS.
///
/// Spec: `docs/superpowers/specs/2026-06-30-ui-overhaul-design.md`

// MARK: - Color tokens

extension Color {
    // Neutrals
    static let suCanvas         = Color(.suCanvas)
    static let suSurface        = Color(.suSurface)
    static let suSurfaceMuted   = Color(.suSurfaceMuted)
    static let suBorder         = Color(.suBorder)
    static let suInkPrimary     = Color(.suInkPrimary)
    static let suInkSecondary   = Color(.suInkSecondary)
    static let suInkTertiary    = Color(.suInkTertiary)

    // Accent
    static let suAccent         = Color(.suAccent)
    static let suAccentDeep     = Color(.suAccentDeep)
    static let suAccentSurface  = Color(.suAccentSurface)

    // Semantic
    static let suWarning        = Color(.suWarning)
    static let suSuccess        = Color(.suSuccess)
    static let suDanger         = Color(.suDanger)
}

extension UIColor {
    static let suCanvas         = dynamic(light: 0xFBF8F2, dark: 0x16110D)
    static let suSurface        = dynamic(light: 0xFFFFFF, dark: 0x1F1A14)
    static let suSurfaceMuted   = dynamic(light: 0xF4F0E8, dark: 0x28221B)
    static let suBorder         = dynamic(light: 0xE8E3DA, dark: 0x3A332B)
    static let suInkPrimary     = dynamic(light: 0x1A1410, dark: 0xF5EFE3)
    static let suInkSecondary   = dynamic(light: 0x6B6358, dark: 0xA89F92)
    static let suInkTertiary    = dynamic(light: 0x8A8378, dark: 0x75695C)

    static let suAccent         = dynamic(light: 0xFFCB74, dark: 0xFFCB74)
    static let suAccentDeep     = dynamic(light: 0xB88838, dark: 0xE2B25A)
    static let suAccentSurface  = dynamic(light: 0xFFF3DC, dark: 0x3D2F12)

    static let suWarning        = dynamic(light: 0xF5A623, dark: 0xF5A623)
    static let suSuccess        = dynamic(light: 0x5BA678, dark: 0x74C091)
    static let suDanger         = dynamic(light: 0xC76B5C, dark: 0xD88474)

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }

    fileprivate convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Spacing

enum SUSpace {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 20
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Radius

enum SURadius {
    static let xs:   CGFloat = 6
    static let sm:   CGFloat = 10
    static let md:   CGFloat = 14
    static let lg:   CGFloat = 20
    /// Used with `.clipShape(Capsule())` typically — but as a CGFloat for codepaths
    /// that need a number (e.g. RoundedRectangle).
    static let pill: CGFloat = 9999
}

// MARK: - Elevation

/// Shadow tokens. Apply via `.suElevation(.e1)`.
enum SUElevation {
    case e0, e1, e2, e3, accent

    var color: Color {
        switch self {
        case .accent: return Color(red: 1.0, green: 0.796, blue: 0.455).opacity(0.35)
        default:      return Color(red: 0.078, green: 0.059, blue: 0.020).opacity(opacity)
        }
    }
    var opacity: Double {
        switch self {
        case .e0: return 0
        case .e1: return 0.04
        case .e2: return 0.06
        case .e3: return 0.10
        case .accent: return 0.35
        }
    }
    var radius: CGFloat {
        switch self {
        case .e0: return 0
        case .e1: return 2
        case .e2: return 16
        case .e3: return 32
        case .accent: return 20
        }
    }
    var y: CGFloat {
        switch self {
        case .e0: return 0
        case .e1: return 1
        case .e2: return 4
        case .e3: return 12
        case .accent: return 6
        }
    }
}

extension View {
    func suElevation(_ level: SUElevation) -> some View {
        shadow(color: level.color, radius: level.radius, x: 0, y: level.y)
    }
}

// MARK: - Motion

enum SUMotion {
    /// 120ms easeOut — button press scale, toggle flips.
    static let fast = Animation.timingCurve(0.2, 0, 0, 1.0, duration: 0.12)
    /// 280ms easeOut — sheet present/dismiss, toast appear, tab indicator slide.
    static let standard = Animation.timingCurve(0.2, 0, 0, 1.0, duration: 0.28)
    /// 440ms easeOut — confirm sheet hand-off, success bloom.
    static let slow = Animation.timingCurve(0.2, 0, 0, 1.0, duration: 0.44)
}
