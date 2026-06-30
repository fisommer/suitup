import SwiftUI

/// Legacy thin wrapper around SUToast. Kept so existing call sites that
/// reference `SavedToast(name: …)` keep compiling without churn during the
/// UI overhaul. New code should use SUToast directly.
struct SavedToast: View {
    let name: String

    var body: some View {
        SUToast(message: name.isEmpty ? "Saved" : "Saved \(name)", icon: "checkmark")
    }
}

#Preview {
    SavedToast(name: "Cream linen shirt")
        .padding()
        .background(Color.suCanvas)
}
