import SwiftUI

/// Empty-state hero block. Icon + serif title + body + primary action.
/// Replaces every existing ContentUnavailableView in the app.
struct SUEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: SUSpace.md) {
            ZStack {
                Circle()
                    .fill(Color.suSurfaceMuted)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.suInkTertiary)
            }
            VStack(spacing: SUSpace.xs) {
                Text(title)
                    .suSectionTitle()
                    .foregroundStyle(Color.suInkPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .suCaption()
                    .foregroundStyle(Color.suInkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SUSpace.md)
            }
            if let actionTitle, let action {
                SUButton(actionTitle, fullWidth: false, action: action)
                    .padding(.top, SUSpace.xs)
            }
        }
        .padding(.vertical, SUSpace.xl)
        .padding(.horizontal, SUSpace.lg)
        .frame(maxWidth: .infinity)
    }
}

#Preview("SUEmptyState") {
    VStack(spacing: SUSpace.lg) {
        SUEmptyState(
            icon: "hanger",
            title: "Your closet is empty",
            message: "Add your first piece — by photo, paste a link, or the share sheet from any product page.",
            actionTitle: "Add item",
            action: {}
        )
    }
    .padding(SUSpace.lg)
    .background(Color.suCanvas)
}
