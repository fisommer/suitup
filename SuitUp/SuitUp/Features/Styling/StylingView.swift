import SwiftUI
import SwiftData

struct StylingView: View {
    let selected: Item

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var closet: [Item]
    @Query private var savedOutfits: [Outfit]
    @Query private var references: [ReferenceLook]

    @State private var phase: Phase = .generating
    @State private var suggestions: [StyleSuggestion] = []
    @State private var previouslySuggested: [[UUID]] = []
    @State private var errorMessage: String?
    @State private var savedSuggestionIds: Set<UUID> = []

    enum Phase { case generating, results, error }

    var body: some View {
        NavigationStack {
            VStack {
                switch phase {
                case .generating: generatingView
                case .results: resultsView
                case .error: errorView
                }
            }
            .background(Color.suCanvas.ignoresSafeArea())
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.suInkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if phase == .results {
                        Button {
                            Task { await regenerate() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color.suInkPrimary)
                        }
                    }
                }
            }
            .task { await generate() }
        }
    }

    // MARK: - Views

    private var generatingView: some View {
        VStack(spacing: SUSpace.md) {
            StoredImage(relativePath: selected.thumbnailPath, contentMode: .fit)
                .frame(width: 110, height: 140)
                .background(Color.suSurfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
            ProgressView()
                .tint(Color.suAccentDeep)
                .controlSize(.regular)
            Text("Styling…")
                .suBody()
                .foregroundStyle(Color.suInkPrimary)
            Text("Looking at your closet, references, and saved outfits")
                .suCaption()
                .foregroundStyle(Color.suInkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SUSpace.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SUSpace.xl) {
                let priorOutfits = savedOutfits.filter { $0.itemIds.contains(selected.id) }
                if !priorOutfits.isEmpty {
                    VStack(alignment: .leading, spacing: SUSpace.md) {
                        SUSectionHeader(title: "You've worn this with", count: priorOutfits.count)
                            .padding(.horizontal, SUSpace.lg)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SUSpace.md) {
                                ForEach(priorOutfits) { outfit in
                                    NavigationLink(value: outfit) {
                                        StoredImage(relativePath: outfit.coverImagePath, contentMode: .fit)
                                            .frame(width: 130, height: 165)
                                            .background(Color.suSurfaceMuted)
                                            .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, SUSpace.lg)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: SUSpace.md) {
                    SUSectionHeader(title: "New ideas", count: suggestions.count)
                        .padding(.horizontal, SUSpace.lg)
                    ForEach(suggestions) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            allItems: closet,
                            isSaved: savedSuggestionIds.contains(suggestion.id)
                        ) {
                            await saveAsOutfit(suggestion)
                        }
                        .padding(.horizontal, SUSpace.lg)
                    }
                }
                Color.clear.frame(height: 100)
            }
            .padding(.top, SUSpace.md)
        }
        .navigationDestination(for: Outfit.self) { outfit in
            OutfitDetailView(outfit: outfit)
        }
    }

    private var errorView: some View {
        VStack(spacing: SUSpace.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.suWarning)
            Text(errorMessage ?? "Something went wrong")
                .suBody()
                .foregroundStyle(Color.suInkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SUSpace.lg)
            SUButton("Try again", fullWidth: false) {
                Task { await generate() }
            }
        }
        .padding(SUSpace.lg)
    }

    // MARK: - Actions

    @MainActor
    private func generate() async {
        phase = .generating
        do {
            let result = try await StylingService().suggestOutfits(
                for: selected,
                closet: closet,
                savedOutfits: savedOutfits,
                references: references,
                previouslySuggested: previouslySuggested
            )
            suggestions = result
            phase = .results
        } catch {
            print("[Styling] generate failed: \(error)")
            errorMessage = error.localizedDescription
            phase = .error
        }
    }

    @MainActor
    private func regenerate() async {
        previouslySuggested.append(contentsOf: suggestions.map { $0.itemIds })
        await generate()
    }

    @MainActor
    private func saveAsOutfit(_ suggestion: StyleSuggestion) async {
        let items = closet.filter { suggestion.itemIds.contains($0.id) }
        let collage = CollageRenderer.render(items: items)
        let id = UUID()
        do {
            let coverPath = try ImageStore.save(collage, folder: .outfits, name: "\(id)", maxDimension: 1024)
            let outfit = Outfit(
                id: id,
                name: suggestion.name,
                itemIds: suggestion.itemIds,
                coverImagePath: coverPath,
                source: .savedFromStyling,
                rationale: suggestion.rationale
            )
            modelContext.insert(outfit)
            try? modelContext.save()
            savedSuggestionIds.insert(suggestion.id)
        } catch {
            print("[Styling] Save outfit failed: \(error)")
        }
    }
}

private struct SuggestionCard: View {
    let suggestion: StyleSuggestion
    let allItems: [Item]
    let isSaved: Bool
    let onSave: () async -> Void

    private var orderedItems: [Item] {
        let lookup = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        return suggestion.itemIds.compactMap { lookup[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SUSpace.md) {
            HStack(alignment: .top, spacing: SUSpace.md) {
                CollageThumb(items: orderedItems)
                    .frame(width: 130, height: 165)
                    .background(Color.suSurfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: SUSpace.xs) {
                    Text(suggestion.name)
                        .suHeadline()
                        .foregroundStyle(Color.suInkPrimary)
                    Text(suggestion.rationale)
                        .suCaption()
                        .foregroundStyle(Color.suInkSecondary)
                        .lineLimit(5)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SUSpace.sm) {
                    ForEach(orderedItems) { item in
                        VStack(spacing: 4) {
                            StoredImage(relativePath: item.thumbnailPath, contentMode: .fill)
                                .frame(width: 50, height: 65)
                                .background(Color.suSurfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous))
                            Text(item.name)
                                .font(.custom("Inter Variable", size: 10))
                                .foregroundStyle(Color.suInkTertiary)
                                .lineLimit(1)
                                .frame(maxWidth: 60)
                        }
                    }
                }
            }
            SUButton(
                isSaved ? "Saved" : "Save outfit",
                style: isSaved ? .disabled : .secondary,
                icon: isSaved ? "bookmark.fill" : "bookmark"
            ) {
                Task { await onSave() }
            }
        }
        .padding(SUSpace.md)
        .background(Color.suSurface)
        .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SURadius.md, style: .continuous)
                .strokeBorder(Color.suBorder, lineWidth: 1)
        )
    }
}
