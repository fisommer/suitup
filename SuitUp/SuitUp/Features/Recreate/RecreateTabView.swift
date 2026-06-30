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
            ZStack(alignment: .top) {
                Color.suCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SUSpace.xl) {
                        Color.clear.frame(height: headerHeight)

                        if !wanted.isEmpty {
                            VStack(alignment: .leading, spacing: SUSpace.md) {
                                SUSectionHeader(title: "Wishlist", count: wanted.count)
                                    .padding(.horizontal, SUSpace.lg)
                                VStack(spacing: SUSpace.sm) {
                                    ForEach(wanted) { w in
                                        wishlistRow(w)
                                    }
                                }
                                .padding(.horizontal, SUSpace.lg)
                            }
                        }

                        VStack(alignment: .leading, spacing: SUSpace.md) {
                            SUSectionHeader(title: "History", count: attempts.isEmpty ? nil : attempts.count)
                                .padding(.horizontal, SUSpace.lg)
                            if attempts.isEmpty {
                                Text("No recreate attempts yet.")
                                    .suBody()
                                    .foregroundStyle(Color.suInkTertiary)
                                    .padding(.horizontal, SUSpace.lg)
                            } else {
                                VStack(spacing: SUSpace.sm) {
                                    ForEach(attempts) { a in
                                        NavigationLink(value: a) {
                                            SUItemCard(
                                                imagePath: a.sourceImagePath,
                                                title: a.name ?? "Recreate attempt",
                                                subtitle: "\(a.recreatableCount) of \(a.totalPieceCount) recreatable · \(a.createdAt.formatted(date: .abbreviated, time: .omitted))"
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, SUSpace.lg)
                            }
                        }

                        Color.clear.frame(height: 100)
                    }
                }
                .navigationDestination(for: RecreateAttempt.self) { RecreateResultView(attempt: $0) }

                headerRow
                    .padding(.horizontal, SUSpace.lg)
                    .padding(.top, SUSpace.md)
                    .padding(.bottom, SUSpace.lg)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.suCanvas
                            .opacity(0.92)
                            .background(.ultraThinMaterial)
                    )
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAdd) { NewRecreateSheet() }
        }
    }

    private var headerHeight: CGFloat { 80 }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recreate")
                .suTitle()
                .foregroundStyle(Color.suInkPrimary)
            Spacer()
        }
    }

    private func wishlistRow(_ w: WantedPiece) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(w.pieceDescription)
                .suBody()
                .foregroundStyle(Color.suInkPrimary)
                .lineLimit(2)
            Text("\(w.category.displayName) · \(w.colors.joined(separator: ", "))")
                .suCaption()
                .foregroundStyle(Color.suInkTertiary)
        }
        .padding(SUSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.suSurface)
        .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                .strokeBorder(Color.suBorder, lineWidth: 1)
        )
    }
}

struct NewRecreateSheet: View {
    /// Optional image preloaded from the share extension. When set, picker step is skipped.
    var preloadedImage: UIImage? = nil
    /// Optional name prefill (e.g. inferred from a shared post). Editable.
    var prefilledName: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var closet: [Item]
    @Query private var references: [ReferenceLook]
    @State private var libItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var name: String = ""
    @State private var phase: Phase = .input
    @State private var errorMessage: String?

    enum Phase { case input, analyzing }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.suCanvas.ignoresSafeArea()

                switch phase {
                case .input: inputView
                case .analyzing: analyzingView
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: libItem) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await MainActor.run { sourceImage = img }
                    }
                }
            }
            .onAppear {
                if sourceImage == nil, let preloadedImage {
                    sourceImage = preloadedImage
                }
                if name.isEmpty, let prefilledName, !prefilledName.isEmpty {
                    name = prefilledName
                }
            }
            .alert("Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }), actions: { Button("OK", role: .cancel) {} }, message: { Text(errorMessage ?? "") })
        }
    }

    private var inputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SUSpace.lg) {
                HStack {
                    Text("Recreate look")
                        .suSectionTitle()
                        .foregroundStyle(Color.suInkPrimary)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .font(.custom("Inter Variable", size: 14).weight(.medium))
                        .foregroundStyle(Color.suInkSecondary)
                }
                .padding(.horizontal, SUSpace.lg)
                .padding(.top, SUSpace.lg)

                SUTextField(
                    label: "Outfit name",
                    text: $name,
                    placeholder: "e.g. linen Riviera fit",
                    autocorrect: false
                )
                .padding(.horizontal, SUSpace.lg)

                Text("Used later if you save the matched items as an outfit. Optional — you can rename it after.")
                    .suCaption()
                    .foregroundStyle(Color.suInkTertiary)
                    .padding(.horizontal, SUSpace.lg)

                VStack(alignment: .leading, spacing: SUSpace.md) {
                    SUSectionHeader(title: "Outfit image")
                        .padding(.horizontal, SUSpace.lg)

                    if let sourceImage {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                            .background(Color.suSurfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
                            .padding(.horizontal, SUSpace.lg)
                    } else {
                        PhotosPicker(selection: $libItem, matching: .images, photoLibrary: .shared()) {
                            HStack(spacing: SUSpace.md) {
                                ZStack {
                                    Circle()
                                        .fill(Color.suAccentSurface)
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 16, weight: .light))
                                        .foregroundStyle(Color.suAccentDeep)
                                }
                                Text("Pick from library")
                                    .suHeadline()
                                    .foregroundStyle(Color.suInkPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundStyle(Color.suInkTertiary)
                            }
                            .padding(SUSpace.md)
                            .background(Color.suSurface)
                            .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                                    .strokeBorder(Color.suBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, SUSpace.lg)
                    }
                }

                if sourceImage != nil {
                    SUButton("Analyze", icon: "wand.and.stars") {
                        Task { await analyze() }
                    }
                    .padding(.horizontal, SUSpace.lg)
                    .padding(.top, SUSpace.sm)
                }

                Spacer().frame(height: SUSpace.lg)
            }
        }
    }

    private var analyzingView: some View {
        VStack(spacing: SUSpace.md) {
            ProgressView()
                .tint(Color.suAccentDeep)
            Text("Analyzing the look against your closet…")
                .suBody()
                .foregroundStyle(Color.suInkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SUSpace.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func analyze() async {
        guard let sourceImage else { return }
        phase = .analyzing
        do {
            let result = try await RecreateService().analyze(image: sourceImage, closet: closet, references: references)
            let id = UUID()
            let sourcePath = try ImageStore.save(sourceImage, folder: .recreate, name: "\(id)", maxDimension: 1024)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let attempt = try RecreateAttempt(
                id: id,
                name: trimmed.isEmpty ? nil : trimmed,
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
    @State private var savedReferenceFlash: Bool = false

    private var itemsById: [UUID: Item] {
        Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }

    private var outfitSaved: Bool { attempt.savedOutfitId != nil }
    private var referenceSaved: Bool { attempt.linkedReferenceLookId != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StoredImage(relativePath: attempt.sourceImagePath).frame(maxHeight: 400)

                VStack(alignment: .leading, spacing: 2) {
                    if let name = attempt.name, !name.isEmpty {
                        Text(name)
                            .font(.title3.bold())
                    }
                    Text("\(attempt.recreatableCount) of \(attempt.totalPieceCount) pieces recreatable")
                        .font(.headline)
                }
                .padding(.horizontal)

                ForEach(Array(attempt.matches.enumerated()), id: \.offset) { _, match in
                    matchRow(match, piece: attempt.parsedPieces[safe: match.pieceIndex])
                        .padding(.horizontal)
                }

                VStack(spacing: 10) {
                    Button {
                        saveMatchedOutfit()
                    } label: {
                        HStack(spacing: 6) {
                            if outfitSaved {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(outfitSaved ? "Saved to Outfits" : "Save matched items as outfit")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(attempt.recreatableCount == 0 || outfitSaved)

                    Button {
                        saveAsReference()
                    } label: {
                        HStack(spacing: 6) {
                            if referenceSaved {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(referenceSaved ? "Saved as reference" : "Save source image as reference")
                        }
                    }
                    .disabled(referenceSaved)
                }
                .padding(.horizontal)
                .padding(.top, 8)
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
                        } else {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
        let outfitName: String = {
            if let n = attempt.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                return n
            }
            return "Recreated look"
        }()
        do {
            let path = try ImageStore.save(collage, folder: .outfits, name: "\(id)", maxDimension: 1024)
            let outfit = Outfit(
                id: id,
                name: outfitName,
                itemIds: matchedIds,
                coverImagePath: path,
                source: .manuallyBuilt,
                rationale: "From recreate attempt"
            )
            modelContext.insert(outfit)
            attempt.savedOutfitId = id
            try? modelContext.save()
            AppEvents.shared.didSaveItem(id: id, name: outfitName)
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
