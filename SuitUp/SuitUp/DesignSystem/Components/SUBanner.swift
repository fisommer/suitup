import SwiftUI

/// Inline non-blocking message banner. Variants: warning, success, info.
/// Used inside forms / screens — never as a sheet or alert.
struct SUBanner: View {
    enum Style { case warning, success, info }

    let message: String
    let style: Style

    init(_ message: String, style: Style = .info) {
        self.message = message
        self.style = style
    }

    var body: some View {
        HStack(alignment: .top, spacing: SUSpace.sm) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(message)
                .suCaption()
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SUSpace.md)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var iconName: String {
        switch style {
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        }
    }
    private var iconColor: Color {
        switch style {
        case .warning: return .suWarning
        case .success: return .suSuccess
        case .info:    return .suInkTertiary
        }
    }
    private var textColor: Color {
        switch style {
        case .warning: return Color(red: 0.48, green: 0.37, blue: 0.10)
        case .success: return Color(red: 0.18, green: 0.42, blue: 0.28)
        case .info:    return .suInkSecondary
        }
    }
    private var backgroundColor: Color {
        switch style {
        case .warning: return Color.suWarning.opacity(0.12)
        case .success: return Color.suSuccess.opacity(0.12)
        case .info:    return .suSurfaceMuted
        }
    }
    private var borderColor: Color {
        switch style {
        case .warning: return Color.suWarning.opacity(0.35)
        case .success: return Color.suSuccess.opacity(0.35)
        case .info:    return .suBorder
        }
    }
}

#Preview("SUBanner") {
    VStack(spacing: SUSpace.md) {
        SUBanner("URL had a color variant we couldn't resolve. Please pick the color manually.", style: .warning)
        SUBanner("Outfit saved to your closet.", style: .success)
        SUBanner("Background couldn't be removed automatically — using the original image.", style: .info)
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
