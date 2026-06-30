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

// Palette mirrors SuitUp/DesignSystem/Theme.swift — duplicated here because the
// share extension target doesn't have access to the design system files.
private extension Color {
    static let suxCanvas        = Color(red: 0.984, green: 0.973, blue: 0.949)  // #FBF8F2
    static let suxSurface       = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let suxSurfaceMuted  = Color(red: 0.957, green: 0.941, blue: 0.910)  // #F4F0E8
    static let suxBorder        = Color(red: 0.910, green: 0.890, blue: 0.855)  // #E8E3DA
    static let suxInkPrimary    = Color(red: 0.102, green: 0.078, blue: 0.063)  // #1A1410
    static let suxInkSecondary  = Color(red: 0.420, green: 0.388, blue: 0.345)  // #6B6358
    static let suxInkTertiary   = Color(red: 0.541, green: 0.514, blue: 0.471)  // #8A8378
    static let suxAccent        = Color(red: 1.000, green: 0.796, blue: 0.455)  // #FFCB74
    static let suxAccentDeep    = Color(red: 0.722, green: 0.533, blue: 0.220)  // #B88838
    static let suxAccentSurface = Color(red: 1.000, green: 0.953, blue: 0.863)  // #FFF3DC
    static let suxSuccess       = Color(red: 0.357, green: 0.651, blue: 0.471)
    static let suxDanger        = Color(red: 0.780, green: 0.420, blue: 0.361)
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
            ZStack {
                Color.suxCanvas.ignoresSafeArea()

                VStack(spacing: 16) {
                    Text("Add to SuitUp")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.suxInkPrimary)
                        .padding(.top, 12)

                    Group {
                        if didHandOff {
                            handOffView
                        } else {
                            switch kind {
                            case .unknown:
                                ProgressView()
                                    .tint(Color.suxAccentDeep)
                                    .padding(.vertical, 24)
                            case .none:
                                Text("Nothing shareable found.")
                                    .foregroundStyle(Color.suxInkSecondary)
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
                            .foregroundStyle(Color.suxDanger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer()

                    if !didHandOff {
                        Button("Cancel", role: .cancel) { onCancel() }
                            .foregroundStyle(Color.suxInkSecondary)
                            .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .task { await detectKind() }
        }
    }

    private var handOffView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.suxSuccess)
            Text("Saved")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.suxInkPrimary)
            Text("Open SuitUp to finish →")
                .font(.subheadline)
                .foregroundStyle(Color.suxInkSecondary)
        }
        .padding(.vertical, 24)
        .transition(.opacity)
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, action: String) -> some View {
        Button {
            Task { await route(action: action) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.suxAccentSurface)
                        .frame(width: 36, height: 36)
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color.suxAccentDeep)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.suxInkPrimary)
                Spacer()
                if isWriting {
                    ProgressView().controlSize(.small).tint(Color.suxInkTertiary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(Color.suxInkTertiary)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color.suxSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.suxBorder, lineWidth: 1)
            )
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
