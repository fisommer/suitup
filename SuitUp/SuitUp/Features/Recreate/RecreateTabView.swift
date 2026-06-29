import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct RecreateTabView: View {
    @Query(sort: \RecreateAttempt.createdAt, order: .reverse) private var attempts: [RecreateAttempt]
    @Query(sort: \WantedPiece.createdAt, order: .reverse) private var wanted: [WantedPiece]
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showingAdd = true } label: { Label("New recreate", systemImage: "plus") }
                }
                if !wanted.isEmpty {
                    Section("Wishlist") {
                        ForEach(wanted) { w in
                            VStack(alignment: .leading) {
                                Text(w.pieceDescription)
                                Text("\(w.category.displayName) · \(w.colors.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("History") {
                    if attempts.isEmpty {
                        Text("No recreate attempts yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(attempts) { a in
                            NavigationLink(value: a) {
                                HStack {
                                    StoredImage(relativePath: a.sourceImagePath).frame(width: 60, height: 75)
                                    VStack(alignment: .leading) {
                                        Text("\(a.recreatableCount) of \(a.totalPieceCount) recreatable")
                                        Text(a.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recreate")
            .navigationDestination(for: RecreateAttempt.self) { RecreateResultView(attempt: $0) }
            .sheet(isPresented: $showingAdd) { NewRecreateSheet() }
        }
    }
}

struct NewRecreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var closet: [Item]
    @Query private var references: [ReferenceLook]
    @State private var libItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var phase: Phase = .input
    @State private var errorMessage: String?

    enum Phase { case input, analyzing }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:
                    Form {
                        Section("Pick an outfit image") {
                            PhotosPicker(selection: $libItem, matching: .images, photoLibrary: .shared()) {
                                Label("Pick from library", systemImage: "photo")
                            }
                            if let sourceImage {
                                Image(uiImage: sourceImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 360)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        if sourceImage != nil {
                            Button("Analyze") { Task { await analyze() } }
                        }
                    }
                case .analyzing:
                    VStack { ProgressView("Analyzing…").padding() }
                }
            }
            .navigationTitle("Recreate look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: libItem) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await MainActor.run { sourceImage = img }
                    }
                }
            }
            .alert("Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }), actions: { Button("OK", role: .cancel) {} }, message: { Text(errorMessage ?? "") })
        }
    }

    @MainActor
    private func analyze() async {
        guard let sourceImage else { return }
        phase = .analyzing
        do {
            let result = try await RecreateService().analyze(image: sourceImage, closet: closet, references: references)
            let id = UUID()
            let sourcePath = try ImageStore.save(sourceImage, folder: .recreate, name: "\(id)", maxDimension: 1024)
            let attempt = try RecreateAttempt(
                id: id,
                sourceImagePath: sourcePath,
                parsedPieces: result.parsedPieces,
                matches: result.matches
            )
            modelContext.insert(attempt)
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            phase = .input
        }
    }
}

struct RecreateResultView: View {
    @Bindable var attempt: RecreateAttempt
    @Query private var allItems: [Item]
    @Environment(\.modelContext) private var modelContext

    private var itemsById: [UUID: Item] {
        Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StoredImage(relativePath: attempt.sourceImagePath).frame(maxHeight: 400)
                Text("\(attempt.recreatableCount) of \(attempt.totalPieceCount) pieces recreatable")
                    .font(.headline)
                    .padding(.horizontal)
                ForEach(Array(attempt.matches.enumerated()), id: \.offset) { _, match in
                    matchRow(match, piece: attempt.parsedPieces[safe: match.pieceIndex])
                        .padding(.horizontal)
                }
                Button("Save matched items as outfit") { saveMatchedOutfit() }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .disabled(attempt.recreatableCount == 0)
                Button("Save source image as reference") { saveAsReference() }
                    .padding(.horizontal)
            }
        }
        .navigationTitle("Recreate")
    }

    private func matchRow(_ match: PieceMatch, piece: ParsedPiece?) -> some View {
        HStack(alignment: .top) {
            Image(systemName: match.status == .matched ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(match.status == .matched ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(piece?.description ?? "Piece").font(.body)
                if match.status == .matched, let id = match.matchedItemId, let item = itemsById[id] {
                    NavigationLink(value: item) {
                        HStack {
                            StoredImage(relativePath: item.thumbnailPath).frame(width: 50, height: 65)
                            VStack(alignment: .leading) {
                                Text(item.name).font(.caption)
                                if let c = match.confidence { Text(c.rawValue).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } else if match.status == .missing {
                    HStack {
                        Text(match.note ?? "Missing from closet").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if match.wantedPieceId == nil {
                            Button("Save as want") { saveAsWant(match: match, piece: piece) }.font(.caption)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func saveAsWant(match: PieceMatch, piece: ParsedPiece?) {
        guard let piece else { return }
        let wanted = WantedPiece(
            pieceDescription: piece.description,
            category: piece.category,
            colors: piece.colors,
            sourceRecreateAttemptId: attempt.id
        )
        modelContext.insert(wanted)
        // Update the match record
        var updated = attempt.matches
        if let idx = updated.firstIndex(where: { $0.pieceIndex == match.pieceIndex }) {
            updated[idx].wantedPieceId = wanted.id
            attempt.matchesJSON = (try? JSONEncoder().encode(updated)) ?? attempt.matchesJSON
        }
        try? modelContext.save()
    }

    @MainActor
    private func saveMatchedOutfit() {
        let matchedIds = attempt.matches.compactMap { $0.matchedItemId }
        let items = matchedIds.compactMap { itemsById[$0] }
        guard !items.isEmpty else { return }
        let collage = CollageRenderer.render(items: items)
        let id = UUID()
        do {
            let path = try ImageStore.save(collage, folder: .outfits, name: "\(id)", maxDimension: 1024)
            let outfit = Outfit(
                id: id,
                name: "Recreated look",
                itemIds: matchedIds,
                coverImagePath: path,
                source: .manuallyBuilt,
                rationale: "From recreate attempt"
            )
            modelContext.insert(outfit)
            try? modelContext.save()
        } catch { print(error) }
    }

    private func saveAsReference() {
        let id = UUID()
        guard let img = ImageStore.load(attempt.sourceImagePath) else { return }
        do {
            let path = try ImageStore.save(img, folder: .references, name: "\(id)", maxDimension: 1024)
            let thumb = try ImageStore.save(img, folder: .references, name: "\(id)-thumb", maxDimension: 256)
            let ref = ReferenceLook(id: id, imagePath: path, thumbnailPath: thumb, source: .library)
            modelContext.insert(ref)
            attempt.linkedReferenceLookId = id
            try? modelContext.save()
        } catch { print(error) }
    }
}

extension Array {
    subscript(safe idx: Int) -> Element? { indices.contains(idx) ? self[idx] : nil }
}
