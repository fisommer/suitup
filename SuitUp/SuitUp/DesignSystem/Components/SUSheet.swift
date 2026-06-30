import SwiftUI

/// Consistent sheet chrome wrapper. Adds a small drag handle and warm Canvas background.
/// Use by wrapping sheet content: `SUSheet { content }`.
struct SUSheet<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.suBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, SUSpace.sm)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.suCanvas)
    }
}

#Preview("SUSheet") {
    SUSheet {
        VStack(spacing: SUSpace.lg) {
            Text("Sheet content")
                .suTitle()
            Text("Wraps any sheet body. The handle + Canvas background are consistent across all modals.")
                .suBody()
                .foregroundStyle(Color.suInkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(SUSpace.lg)
    }
}
