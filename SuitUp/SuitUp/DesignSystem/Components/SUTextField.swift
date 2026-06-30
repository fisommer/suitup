import SwiftUI

/// Standard form text field with uppercase label above and consistent chrome.
/// Focused state shows the honey ring (one of the few places gold appears in the UI).
struct SUTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var error: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = true

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .suLabel()
                .foregroundStyle(Color.suInkTertiary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(!autocorrect)
                }
            }
            .focused($isFocused)
            .suBody()
            .foregroundStyle(Color.suInkPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.suSurface)
            .clipShape(RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused || error != nil ? 1.5 : 1)
            )
            .shadow(color: isFocused ? Color.suAccent.opacity(0.18) : .clear,
                    radius: 4, x: 0, y: 0)
            .animation(SUMotion.fast, value: isFocused)
            .animation(SUMotion.fast, value: error)

            if let error {
                Text(error)
                    .suCaption()
                    .foregroundStyle(Color.suDanger)
            }
        }
    }

    private var borderColor: Color {
        if error != nil { return .suDanger }
        if isFocused    { return .suAccent }
        return .suBorder
    }
}

#Preview("SUTextField states") {
    @Previewable @State var s1 = ""
    @Previewable @State var s2 = "Burgundy"
    @Previewable @State var s3 = ""
    VStack(spacing: SUSpace.lg) {
        SUTextField(label: "Email or username", text: $s1, placeholder: "you@example.com")
        SUTextField(label: "Color", text: $s2)
        SUTextField(label: "Required field", text: $s3, error: "Name is required")
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
