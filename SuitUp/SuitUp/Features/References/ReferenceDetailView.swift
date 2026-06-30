import SwiftUI
import SwiftData

struct ReferenceDetailView: View {
    @Bindable var ref: ReferenceLook
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var noteDraft: String = ""
    @State private var showingDeleteConfirm = false

    init(ref: ReferenceLook) {
        self.ref = ref
        _noteDraft = State(initialValue: ref.note ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SUSpace.lg) {
                StoredImage(relativePath: ref.imagePath, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 500)
                    .background(Color.suSurfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SURadius.lg, style: .continuous))
                    .padding(.horizontal, SUSpace.lg)

                VStack(alignment: .leading, spacing: SUSpace.sm) {
                    Text("Note")
                        .suLabel()
                        .foregroundStyle(Color.suInkTertiary)
                    TextField("Optional", text: $noteDraft, axis: .vertical)
                        .suBody()
                        .foregroundStyle(Color.suInkPrimary)
                        .lineLimit(2...5)
                        .onChange(of: noteDraft) { _, new in
                            ref.note = new.isEmpty ? nil : new
                            try? modelContext.save()
                        }
                }
                .padding(.horizontal, SUSpace.lg)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Added")
                        .suLabel()
                        .foregroundStyle(Color.suInkTertiary)
                    Text(ref.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .suBody()
                        .foregroundStyle(Color.suInkPrimary)
                }
                .padding(.horizontal, SUSpace.lg)

                Color.clear.frame(height: 100)
            }
            .padding(.top, SUSpace.md)
        }
        .background(Color.suCanvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color.suInkPrimary)
            }
        }
        .confirmationDialog(
            "Delete this reference?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                ImageStore.delete(ref.imagePath)
                ImageStore.delete(ref.thumbnailPath)
                modelContext.delete(ref)
                try? modelContext.save()
                dismiss()
            }
        }
    }
}
