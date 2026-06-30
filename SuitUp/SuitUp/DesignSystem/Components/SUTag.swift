import SwiftUI

/// Pill-shaped status/metadata chip. Display-only — never a tappable button.
struct SUTag: View {
    enum Style { case neutral, accent, success, warning }

    let title: String
    let style: Style

    init(_ title: String, style: Style = .neutral) {
        self.title = title
        self.style = style
    }

    var body: some View {
        Text(title)
            .font(.custom("Inter Variable", size: 12).weight(.medium))
            .padding(.horizontal, SUSpace.md)
            .padding(.vertical, 5)
            .foregroundStyle(textColor)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch style {
        case .neutral:  return .suSurfaceMuted
        case .accent:   return .suAccentSurface
        case .success:  return Color.suSuccess.opacity(0.18)
        case .warning:  return Color.suWarning.opacity(0.18)
        }
    }
    private var textColor: Color {
        switch style {
        case .neutral:  return .suInkSecondary
        case .accent:   return .suAccentDeep
        case .success:  return Color(red: 0.18, green: 0.42, blue: 0.28)
        case .warning:  return Color(red: 0.48, green: 0.37, blue: 0.10)
        }
    }
}

#Preview("SUTag variants") {
    HStack(spacing: SUSpace.sm) {
        SUTag("Summer")
        SUTag("Loose")
        SUTag("Casual", style: .accent)
        SUTag("Saved", style: .success)
        SUTag("Needs review", style: .warning)
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
