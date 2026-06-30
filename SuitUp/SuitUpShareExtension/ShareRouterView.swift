//
//  ShareRouterView.swift
//  SuitUpShareExtension
//
//  SwiftUI sheet inside the share extension. Detects the payload kind (image, url, or both)
//  and offers the three actions: save as reference, recreate look, add to closet via URL.
//
//  Writes JSON manifest + image bytes to SharedContainer.inboxURL().
//  The main app drains the inbox on next launch/foreground.
//

import SwiftUI
import UniformTypeIdentifiers

enum SharePayloadKind {
    case image
    case url
    case mixed
    case unknown
    case none
}

struct ShareRouterView: View {
    let inputItems: [NSExtensionItem]
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var kind: SharePayloadKind = .unknown
    @State private var isWriting: Bool = false
    @State private var didHandOff: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Add to SuitUp")
                    .font(.title3.bold())
                    .padding(.top, 8)

                Group {
                    if didHandOff {
                        handOffView
                    } else {
                        switch kind {
                        case .unknown:
                            ProgressView("Detecting…")
                                .padding(.vertical, 24)
                        case .none:
                            Text("Nothing shareable found.")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 24)
                        case .image:
                            actionButton("Save as reference", systemImage: "bookmark", action: "reference")
                            actionButton("Recreate this look", systemImage: "wand.and.stars", action: "recreate")
                        case .url:
                            actionButton("Add to closet (product link)", systemImage: "link", action: "closet-url")
                        case .mixed:
                            actionButton("Save as reference", systemImage: "bookmark", action: "reference")
                            actionButton("Recreate this look", systemImage: "wand.and.stars", action: "recreate")
                            actionButton("Add to closet (product link)", systemImage: "link", action: "closet-url")
                        }
                    }
                }
                .disabled(isWriting)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                if !didHandOff {
                    Button("Cancel", role: .cancel) { onCancel() }
                        .padding(.bottom, 12)
                }
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await detectKind() }
        }
    }

    private var handOffView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Saved")
                .font(.title3.bold())
            Text("Open SuitUp to finish →")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .transition(.opacity)
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, action: String) -> some View {
        Button {
            Task { await route(action: action) }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.body.weight(.semibold))
                Spacer()
                if isWriting {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detection

    private func detectKind() async {
        var sawImage = false
        var sawURL = false
        for item in inputItems {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    sawImage = true
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    sawURL = true
                }
            }
        }
        await MainActor.run {
            if sawImage && sawURL { kind = .mixed }
            else if sawImage { kind = .image }
            else if sawURL { kind = .url }
            else { kind = .none }
        }
    }

    // MARK: - Routing

    private func route(action: String) async {
        await MainActor.run { isWriting = true; errorMessage = nil }
        do {
            try await writePayload(action: action)
            await MainActor.run {
                isWriting = false
                withAnimation(.easeInOut(duration: 0.2)) { didHandOff = true }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { onDone() }
        } catch {
            await MainActor.run {
                isWriting = false
                errorMessage = "Couldn't hand off to SuitUp: \(error.localizedDescription)"
            }
        }
    }

    private func writePayload(action: String) async throws {
        var imageRelativePath: String?
        var url: String?

        // Walk all providers; for v0 take the FIRST image and FIRST url we find.
        // (Instagram carousels with multiple images: we take the first only.)
        for item in inputItems {
            for provider in item.attachments ?? [] {
                if imageRelativePath == nil,
                   provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                   action != "closet-url" || url == nil {
                    if let data = try? await loadImageData(provider) {
                        let id = UUID().uuidString
                        let filename = "\(id).img"
                        let dest = SharedContainer.inboxURL().appendingPathComponent(filename)
                        try data.write(to: dest, options: .atomic)
                        imageRelativePath = filename
                    }
                }
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let u = try? await loadURL(provider) {
                        url = u.absoluteString
                    }
                }
            }
        }

        var payload: [String: Any] = [
            "action": action,
            "timestamp": Date().timeIntervalSince1970,
        ]
        if let imageRelativePath { payload["imagePath"] = imageRelativePath }
        if let url { payload["url"] = url }

        let manifestName = "\(UUID().uuidString).json"
        let manifestURL = SharedContainer.inboxURL().appendingPathComponent(manifestName)
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: manifestURL, options: .atomic)
    }

    private func loadImageData(_ provider: NSItemProvider) async throws -> Data? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, err in
                if let err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(returning: data)
                }
            }
        }
    }

    private func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, err in
                if let err {
                    cont.resume(throwing: err)
                    return
                }
                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let urlString = item as? String, let url = URL(string: urlString) {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
