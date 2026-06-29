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
            Group {
                switch phase {
                case .generating: generatingView
                case .results: resultsView
                case .error: errorView
                }
            }
            .navigationTitle("Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if phase == .results {
                        Button {
                            Task { await regenerate() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task { await generate() }
        }
    }

    // MARK: - Views

    private var generatingView: some View {
        VStack(spacing: 16) {
            StoredImage(relativePath: selected.thumbnailPath, contentMode: .fit)
                .frame(width: 110, height: 140)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            ProgressView("Styling…")
                .controlSize(.regular)
            Text("Looking at your closet, references, and saved outfits")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                let priorOutfits = savedOutfits.filter { $0.itemIds.contains(selected.id) }
                if !priorOutfits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You've worn this with")
                            .font(.headline)
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(priorOutfits) { outfit in
                                    NavigationLink(value: outfit) {
                                        StoredImage(relativePath: outfit.coverImagePath, contentMode: .fit)
                                            .frame(width: 130, height: 165)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("New ideas")
                        .font(.headline)
                        .padding(.horizontal)
                    ForEach(suggestions) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            allItems: closet,
                            isSaved: savedSuggestionIds.contains(suggestion.id)
                        ) {
                            await saveAsOutfit(suggestion)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationDestination(for: Outfit.self) { outfit in
            OutfitDetailView(outfit: outfit)
        }
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(errorMessage ?? "Something went wrong")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try again") {
                Task { await generate() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CollageThumb(items: orderedItems)
                    .frame(width: 130, height: 165)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.name)
                        .font(.headline)
                    Text(suggestion.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(orderedItems) { item in
                        VStack(spacing: 2) {
                            StoredImage(relativePath: item.thumbnailPath, contentMode: .fit)
                                .frame(width: 50, height: 65)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(item.name)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .frame(maxWidth: 50)
                        }
                    }
                }
            }
            Button {
                Task { await onSave() }
            } label: {
                Label(isSaved ? "Saved" : "Save outfit", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSaved)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
