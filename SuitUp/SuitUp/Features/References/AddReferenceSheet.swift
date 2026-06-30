import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddReferenceSheet: View {
    /// Optional image preloaded from the share extension. When set, the picker step is skipped.
    var preloadedImage: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var libItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var note: String = ""
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    Section {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Section {
                        TextField("Optional note (e.g. \"love the layering\")", text: $note, axis: .vertical)
                            .lineLimit(1...3)
                    }
                    Section {
                        Button {
                            save(preview: preview)
                        } label: {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView().controlSize(.small)
                                }
                                Text(isSaving ? "Saving…" : "Add to references")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(isSaving)
                    }
                } else {
                    Section {
                        PhotosPicker(selection: $libItem, matching: .images, photoLibrary: .shared()) {
                            Label("Pick from library", systemImage: "photo")
                        }
                    } footer: {
                        Text("References are outfit photos you find inspiring — from Pinterest, Instagram, fashion editorials. SuitUp uses them as your taste anchor.")
                    }
                }
            }
            .navigationTitle("Add reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: libItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run { preview = img }
                    }
                    await MainActor.run { libItem = nil }
                }
            }
            .onAppear {
                if preview == nil, let preloadedImage {
                    preview = preloadedImage
                }
            }
        }
    }

    private func save(preview: UIImage) {
        isSaving = true
        let id = UUID()
        do {
            let imagePath = try ImageStore.save(preview, folder: .references, name: "\(id)", maxDimension: 1024)
            let thumbPath = try ImageStore.save(preview, folder: .references, name: "\(id)-thumb", maxDimension: 256)
            let ref = ReferenceLook(
                id: id,
                imagePath: imagePath,
                thumbnailPath: thumbPath,
                source: .library,
                note: note.isEmpty ? nil : note
            )
            modelContext.insert(ref)
            try? modelContext.save()
            dismiss()
        } catch {
            print("[AddReference] Save failed: \(error)")
            isSaving = false
        }
    }
}
