import SwiftUI

/// Floating confirmation toast. Replaces the existing SavedToast.
/// Dark warm-ink bg + honey dot + body text.
struct SUToast: View {
    let message: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: SUSpace.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.suAccent)
            } else {
                Circle()
                    .fill(Color.suAccent)
                    .frame(width: 8, height: 8)
            }
            Text(message)
                .font(.custom("Inter Variable", size: 13).weight(.medium))
                .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.95))
        }
        .padding(.horizontal, SUSpace.lg)
        .padding(.vertical, 12)
        .background(Color.suInkPrimary.opacity(0.92))
        .clipShape(Capsule())
        .suElevation(.e3)
    }
}

#Preview("SUToast") {
    VStack(spacing: SUSpace.md) {
        SUToast(message: "Saved to your closet")
        SUToast(message: "Outfit saved", icon: "checkmark")
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
