import SwiftUI
import UIKit

struct PasteURLView: View {
    /// Optional URL preloaded from the share extension. When set, the crawler auto-runs on appear.
    var prefilledURL: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String = ""
    @State private var phase: Phase = .input
    @State private var images: [UIImage] = []
    @State private var selectedIndex: Int = 0
    @State private var crawlResult: CrawlResult?
    @State private var errorMessage: String?
    @State private var draftToConfirm: IdentifiedDraft?
    @State private var didAutoCrawl: Bool = false

    enum Phase { case input, crawling, picker }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input: inputView
                case .crawling: crawlingView
                case .picker: pickerView
                }
            }
            .navigationTitle("Add from link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Crawl failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(errorMessage ?? "") }
            )
            .sheet(item: $draftToConfirm) { holder in
                ItemConfirmView(draft: holder.draft) { _ in
                    dismiss()
                }
            }
            .onAppear {
                guard !didAutoCrawl else { return }
                if urlText.isEmpty, let prefilledURL, !prefilledURL.isEmpty {
                    urlText = prefilledURL
                    didAutoCrawl = true
                    if isValidURL(prefilledURL) {
                        Task { await beginCrawl() }
                    }
                }
            }
        }
    }

    // MARK: - Phases

    private var inputView: some View {
        Form {
            Section {
                TextField("https://…", text: $urlText)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if let clip = UIPasteboard.general.string,
                   clip.lowercased().hasPrefix("http"),
                   clip != urlText {
                    Button {
                        urlText = clip
                    } label: {
                        Label {
                            Text("Paste \"\(clip.prefix(40))…\"")
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "doc.on.clipboard")
                        }
                    }
                }
            } header: {
                Text("Product URL")
            } footer: {
                Text("Works best with major retailers (Zalando, Uniqlo, COS, Zara, H&M, ASOS, etc.).")
            }
            Section {
                Button {
                    Task { await beginCrawl() }
                } label: {
                    HStack {
                        Spacer()
                        Text("Continue")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!isValidURL(urlText))
            }
        }
    }

    private var crawlingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Fetching product details…")
                .foregroundStyle(.secondary)
            if let host = URL(string: urlText)?.host {
                Text(host)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pickerView: some View {
        VStack(spacing: 16) {
            Text("Pick the best photo")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(images.enumerated()), id: \.offset) { idx, img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 260)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(idx == selectedIndex ? Color.accentColor : .clear, lineWidth: 3)
                            )
                            .onTapGesture { selectedIndex = idx }
                    }
                }
                .padding(.horizontal)
            }
            Button {
                Task { await proceedToConfirm() }
            } label: {
                Text("Use selected")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top)
    }

    // MARK: - Actions

    private func isValidURL(_ s: String) -> Bool {
        guard let url = URL(string: s), let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    @MainActor
    private func beginCrawl() async {
        phase = .crawling
        do {
            let result = try await CrawlerClient().crawl(url: urlText)
            guard !result.images.isEmpty else { throw CrawlerError.noImages }
            crawlResult = result

            // Download up to 6 candidate images in parallel.
            let topURLs = Array(result.images.prefix(6))
            let downloaded = try await withThrowingTaskGroup(of: (Int, UIImage).self) { group -> [UIImage] in
                for (idx, urlStr) in topURLs.enumerated() {
                    group.addTask {
                        let img = try await CrawlerClient().downloadImage(urlStr)
                        return (idx, img)
                    }
                }
                var collected: [(Int, UIImage)] = []
                for try await pair in group { collected.append(pair) }
                return collected.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
            }
            images = downloaded
            selectedIndex = 0

            if images.count == 1 {
                // Skip picker, go straight to confirm
                await proceedToConfirm()
            } else {
                phase = .picker
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .input
        }
    }

    @MainActor
    private func proceedToConfirm() async {
        guard let crawl = crawlResult, !images.isEmpty else { return }
        let chosen = images[selectedIndex]

        let outcome = await BackgroundRemoval.attemptRemoval(from: chosen)
        let bgRemoved: UIImage
        let bgSucceeded: Bool
        switch outcome {
        case .removed(let img):
            bgRemoved = img
            bgSucceeded = true
        case .noSubjectFound(let img), .failed(_, let img):
            bgRemoved = img
            bgSucceeded = false
        }

        var draft = ItemConfirmDraft(
            originalImage: chosen,
            bgRemovedImage: bgRemoved,
            useBackgroundRemoved: bgSucceeded
        )
        draft.bgRemovalSucceeded = bgSucceeded
        draft.source = .urlCrawl
        draft.sourceUrl = urlText
        draft.name = crawl.data.name ?? ""
        draft.brand = crawl.data.brand ?? ""
        draft.colors = crawl.data.colors ?? []
        draft.material = crawl.data.materials?.first ?? ""
        if !draft.material.isEmpty {
            draft.materialIsGuess = false
        }
        if let cat = crawl.data.category, let mapped = mapCategory(cat) {
            draft.category = mapped
        }
        draft.notes = crawl.data.description ?? ""
        if let domain = URL(string: urlText)?.host {
            draft.purchasedFrom = domain
        }
        if let p = crawl.data.price {
            draft.price = Decimal(p.value)
        }
        draftToConfirm = IdentifiedDraft(draft: draft)
    }

    private func mapCategory(_ raw: String) -> ItemCategory? {
        let s = raw.lowercased()
        if s.contains("shoe") || s.contains("sneaker") || s.contains("boot") || s.contains("loafer") || s.contains("sandal") {
            return .footwear
        }
        if s.contains("jacket") || s.contains("coat") || s.contains("hoodie") || s.contains("blazer") || s.contains("parka") {
            return .outerwear
        }
        if s.contains("pant") || s.contains("trouser") || s.contains("jean") || s.contains("short") || s.contains("chino") || s.contains("skirt") {
            return .bottom
        }
        if s.contains("dress") || s.contains("jumpsuit") || s.contains("overall") {
            return .fullBody
        }
        if s.contains("hat") || s.contains("scarf") || s.contains("belt") || s.contains("bag") || s.contains("glove") {
            return .accessory
        }
        return .top
    }
}

private struct IdentifiedDraft: Identifiable {
    let id = UUID()
    let draft: ItemConfirmDraft
}
