import SwiftUI

/// Primary action button. Five style variants; one consistent press feedback.
///
/// Pairing rule: when used next to a secondary button, both must share the same
/// color family. Use `SUButtonGroup(primary:secondary:)` to enforce this.
struct SUButton: View {
    enum Style {
        case primary, secondary, tertiary, destructive, disabled
    }

    let title: String
    let style: Style
    let action: () -> Void
    var icon: String? = nil
    var isLoading: Bool = false
    var fullWidth: Bool = true

    init(
        _ title: String,
        style: Style = .primary,
        icon: String? = nil,
        isLoading: Bool = false,
        fullWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.icon = icon
        self.isLoading = isLoading
        self.fullWidth = fullWidth
        self.action = action
    }

    @State private var isPressed = false

    var body: some View {
        Button(action: { if !isDisabled { action() } }) {
            HStack(spacing: SUSpace.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foregroundColor)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                }
                Text(title)
                    .suHeadline()
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, SUSpace.lg)
            .padding(.vertical, 14)
            .foregroundStyle(foregroundColor)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isPressed ? 0.92 : 1.0)
            .animation(SUMotion.fast, value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        ._onButtonGesture { isPressed = $0 } perform: {}
    }

    private var isDisabled: Bool { style == .disabled }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:  return Color(.suSurface)
        case .secondary, .tertiary:   return .suInkPrimary
        case .disabled:               return .suInkTertiary
        }
    }
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:      Color.suInkPrimary
        case .secondary:    Color.suSurface
        case .tertiary:     Color.clear
        case .destructive:  Color.suDanger
        case .disabled:     Color.suBorder
        }
    }
    private var borderColor: Color {
        switch style {
        case .secondary:    return .suInkPrimary
        default:            return .clear
        }
    }
    private var borderWidth: CGFloat {
        switch style {
        case .secondary:    return 1.5
        default:            return 0
        }
    }
}

/// Two-button row that enforces same color family between primary + secondary.
///
/// Today this only supports the near-black family. The struct exists so that
/// callers always use a single API instead of hand-rolling two buttons in an
/// HStack, which can drift visually.
struct SUButtonGroup: View {
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryAction: () -> Void
    var primaryIcon: String? = nil
    var primaryIsLoading: Bool = false

    var body: some View {
        VStack(spacing: SUSpace.sm) {
            SUButton(primaryTitle, style: .primary, icon: primaryIcon, isLoading: primaryIsLoading, action: primaryAction)
            SUButton(secondaryTitle, style: .secondary, action: secondaryAction)
        }
    }
}

#Preview("SUButton variants") {
    VStack(spacing: SUSpace.md) {
        SUButton("Save outfit") {}
        SUButton("Edit details", style: .secondary) {}
        SUButton("Cancel", style: .tertiary) {}
        SUButton("Clear all data", style: .destructive) {}
        SUButton("Save outfit", style: .disabled) {}
        SUButton("Saving…", isLoading: true) {}
        SUButton("Add item", icon: "plus") {}
        SUButtonGroup(
            primaryTitle: "Style this piece",
            primaryAction: {},
            secondaryTitle: "Edit details",
            secondaryAction: {}
        )
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
