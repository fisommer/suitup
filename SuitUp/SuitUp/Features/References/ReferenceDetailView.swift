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
            VStack(alignment: .leading, spacing: 16) {
                StoredImage(relativePath: ref.imagePath, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 500)
                    .background(Color(.secondarySystemBackground))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    TextField("Optional", text: $noteDraft, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(.horizontal)
                        .onChange(of: noteDraft) { _, new in
                            ref.note = new.isEmpty ? nil : new
                            try? modelContext.save()
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ref.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.body)
                }
                .padding(.horizontal)
            }
        }
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
