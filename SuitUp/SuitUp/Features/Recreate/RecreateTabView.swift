import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct RecreateTabView: View {
    @Query(sort: \RecreateAttempt.createdAt, order: .reverse) private var attempts: [RecreateAttempt]
    @Query(sort: \WantedPiece.createdAt, order: .reverse) private var wanted: [WantedPiece]
    @State private var showingAdd = false
    @State private var navPath = NavigationPath()
    @StateObject private var events = AppEvents.shared

    var body: some View {
        NavigationStack(path: $navPath) {
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

                if events.showSavedToast {
                    SUToast(message: "Saved \(events.lastSavedItemName ?? "")")
                        .padding(.top, headerHeight + SUSpace.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(SUMotion.standard, value: events.showSavedToast)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAdd) {
                NewRecreateSheet(onCompleted: { attempt in
                    showingAdd = false
                    // Push the just-created attempt onto the nav stack so the user lands on
                    // the result detail directly instead of the overview.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        navPath.append(attempt)
                    }
                })
            }
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
    /// Called when the analyze step succeeds and the attempt is saved. Receives the new attempt
    /// so the presenter can navigate directly to its detail view.
    var onCompleted: ((RecreateAttempt) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var closet: [Item]
    @Query private var references: [ReferenceLook]
    @State private var libItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var name: String = ""
    @State private var phase: Phase = .input
    @State private var errorMessage: String?
    @State private var presentationDetent: PresentationDetent = .medium

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
            .presentationDetents([.medium, .large], selection: $presentationDetent)
            .presentationDragIndicator(.visible)
            .onChange(of: libItem) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await MainActor.run {
                            sourceImage = img
                            // Once an image is picked, expand the sheet so the user can see it + the analyze button.
                            withAnimation(SUMotion.standard) { presentationDetent = .large }
                        }
                    }
                }
            }
            .onAppear {
                if sourceImage == nil, let preloadedImage {
                    sourceImage = preloadedImage
                    presentationDetent = .large
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

            // Use the user-typed name if present, otherwise the AI's suggestion, otherwise nil.
            let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName: String? = !typed.isEmpty
                ? typed
                : (result.suggestedName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { $0.isEmpty ? nil : $0 })

            let id = UUID()
            let sourcePath = try ImageStore.save(sourceImage, folder: .recreate, name: "\(id)", maxDimension: 1024)
            let attempt = try RecreateAttempt(
                id: id,
                name: finalName,
                sourceImagePath: sourcePath,
                parsedPieces: result.parsedPieces,
                matches: result.matches
            )
            modelContext.insert(attempt)
            try? modelContext.save()
            AppEvents.shared.didSaveItem(id: id, name: finalName ?? "Recreate attempt")
            if let onCompleted {
                onCompleted(attempt)
            } else {
                dismiss()
            }
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
    @State private var nameDraft: String = ""

    private var itemsById: [UUID: Item] {
        Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }

    private var outfitSaved: Bool { attempt.savedOutfitId != nil }
    private var referenceSaved: Bool { attempt.linkedReferenceLookId != nil }

    private var matchedMatches: [PieceMatch] { attempt.matches.filter { $0.status == .matched } }
    private var missingMatches: [PieceMatch] { attempt.matches.filter { $0.status == .missing } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SUSpace.lg) {
                StoredImage(relativePath: attempt.sourceImagePath, contentMode: .fit)
                    .frame(maxHeight: 380)
                    .frame(maxWidth: .infinity)
                    .background(Color.suSurfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SURadius.lg, style: .continuous))
                    .padding(.horizontal, SUSpace.lg)

                VStack(alignment: .leading, spacing: SUSpace.sm) {
                    SUTextField(
                        label: "Outfit name",
                        text: $nameDraft,
                        placeholder: "Tap to name this look",
                        autocorrect: false
                    )
                    .onChange(of: nameDraft) { _, new in
                        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                        attempt.name = trimmed.isEmpty ? nil : trimmed
                        try? modelContext.save()
                    }
                    Text("\(attempt.recreatableCount) of \(attempt.totalPieceCount) pieces matched from your closet.")
                        .suCaption()
                        .foregroundStyle(Color.suInkSecondary)
                }
                .padding(.horizontal, SUSpace.lg)

                if !matchedMatches.isEmpty {
                    VStack(alignment: .leading, spacing: SUSpace.md) {
                        SUSectionHeader(title: "In your closet", count: matchedMatches.count)
                            .padding(.horizontal, SUSpace.lg)

                        VStack(spacing: SUSpace.sm) {
                            ForEach(Array(matchedMatches.enumerated()), id: \.offset) { _, match in
                                matchedRow(match)
                            }
                        }
                        .padding(.horizontal, SUSpace.lg)
                    }
                }

                if !missingMatches.isEmpty {
                    VStack(alignment: .leading, spacing: SUSpace.md) {
                        SUSectionHeader(title: "Missing", count: missingMatches.count)
                            .padding(.horizontal, SUSpace.lg)

                        VStack(spacing: SUSpace.sm) {
                            ForEach(Array(missingMatches.enumerated()), id: \.offset) { _, match in
                                missingRow(match)
                            }
                        }
                        .padding(.horizontal, SUSpace.lg)
                    }
                }

                VStack(spacing: SUSpace.sm) {
                    SUButton(
                        outfitSaved ? "Saved to Outfits" : "Save matched items as outfit",
                        style: (attempt.recreatableCount == 0 || outfitSaved) ? .disabled : .primary,
                        icon: outfitSaved ? "checkmark.circle.fill" : nil
                    ) {
                        saveMatchedOutfit()
                    }

                    SUButton(
                        referenceSaved ? "Saved as reference" : "Save source image as reference",
                        style: referenceSaved ? .disabled : .secondary,
                        icon: referenceSaved ? "checkmark.circle.fill" : nil
                    ) {
                        saveAsReference()
                    }
                }
                .padding(.horizontal, SUSpace.lg)
                .padding(.top, SUSpace.sm)

                Color.clear.frame(height: 100)
            }
            .padding(.top, SUSpace.md)
        }
        .background(Color.suCanvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nameDraft = attempt.name ?? ""
        }
    }

    private func matchedRow(_ match: PieceMatch) -> some View {
        let piece = attempt.parsedPieces[safe: match.pieceIndex]
        let alternatives = match.matchedItemIds.compactMap { itemsById[$0] }

        return HStack(alignment: .top, spacing: SUSpace.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.suSuccess)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: SUSpace.sm) {
                Text(piece?.description ?? "Piece")
                    .suBody()
                    .foregroundStyle(Color.suInkPrimary)

                if alternatives.count > 1 {
                    // Multiple matches — horizontal carousel of alternatives.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(alternatives.count) closet options")
                            .suLabel()
                            .foregroundStyle(Color.suInkTertiary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SUSpace.sm) {
                                ForEach(alternatives) { item in
                                    NavigationLink(value: item) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            StoredImage(relativePath: item.thumbnailPath, contentMode: .fill)
                                                .frame(width: 60, height: 78)
                                                .background(Color.suSurfaceMuted)
                                                .clipShape(RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous))
                                            Text(item.name)
                                                .font(.custom("Inter Variable", size: 10).weight(.medium))
                                                .foregroundStyle(Color.suInkPrimary)
                                                .lineLimit(1)
                                                .frame(width: 60, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else if let item = alternatives.first {
                    // Single match — full inline row.
                    NavigationLink(value: item) {
                        HStack(spacing: SUSpace.sm) {
                            StoredImage(relativePath: item.thumbnailPath, contentMode: .fill)
                                .frame(width: 44, height: 56)
                                .background(Color.suSurfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .suCaption()
                                    .foregroundStyle(Color.suInkPrimary)
                                if let c = match.confidence {
                                    Text(c.rawValue)
                                        .suCaption()
                                        .foregroundStyle(Color.suInkTertiary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .light))
                                .foregroundStyle(Color.suInkTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
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

    private func missingRow(_ match: PieceMatch) -> some View {
        let piece = attempt.parsedPieces[safe: match.pieceIndex]

        return VStack(alignment: .leading, spacing: SUSpace.sm) {
            HStack(alignment: .top, spacing: SUSpace.md) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.suInkTertiary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(piece?.description ?? "Piece")
                        .suBody()
                        .foregroundStyle(Color.suInkPrimary)
                    if let note = match.note, !note.isEmpty {
                        Text(note)
                            .suCaption()
                            .foregroundStyle(Color.suInkTertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            // Chip-style "Save as want" button — clearly tappable.
            HStack {
                Spacer()
                if match.wantedPieceId == nil {
                    Button {
                        saveAsWant(match: match, piece: piece)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 11, weight: .light))
                            Text("Save as want")
                                .font(.custom("Inter Variable", size: 12).weight(.semibold))
                        }
                        .foregroundStyle(Color.suAccentDeep)
                        .padding(.horizontal, SUSpace.md)
                        .padding(.vertical, 6)
                        .background(Color.suAccentSurface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .light))
                        Text("Saved to wishlist")
                            .font(.custom("Inter Variable", size: 12).weight(.medium))
                    }
                    .foregroundStyle(Color.suInkTertiary)
                    .padding(.horizontal, SUSpace.md)
                    .padding(.vertical, 6)
                    .background(Color.suSurfaceMuted)
                    .clipShape(Capsule())
                }
            }
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
