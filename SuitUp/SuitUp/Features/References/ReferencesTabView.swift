import SwiftUI
import SwiftData

struct ReferencesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReferenceLook.createdAt, order: .reverse) private var refs: [ReferenceLook]
    @State private var showingAdd = false

    /// Pinterest-style alternating split: first ref → left, second → right, alternating.
    private var leftColumn: [ReferenceLook] {
        refs.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }
    }
    private var rightColumn: [ReferenceLook] {
        refs.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.suCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Spacer matching the floating header height
                        Color.clear.frame(height: headerHeight)

                        if refs.isEmpty {
                            VStack {
                                Spacer(minLength: 40)
                                SUEmptyState(
                                    icon: "sparkles",
                                    title: "No references yet",
                                    message: "Save 15–30 outfits you love to teach SuitUp your taste.",
                                    actionTitle: "Add reference",
                                    action: { showingAdd = true }
                                )
                                Spacer(minLength: 40)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            HStack(alignment: .top, spacing: SUSpace.md) {
                                masonryColumn(items: leftColumn)
                                masonryColumn(items: rightColumn)
                            }
                            .padding(.horizontal, SUSpace.lg)
                        }

                        Color.clear.frame(height: 100)
                    }
                }
                .navigationDestination(for: ReferenceLook.self) {
                    ReferenceDetailView(ref: $0)
                }

                // Floating header — stays anchored at top while content scrolls under it.
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
            .sheet(isPresented: $showingAdd) {
                AddReferenceSheet()
            }
        }
    }

    /// Approximate height of the floating header — Title row + paddings.
    private var headerHeight: CGFloat { 80 }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("References")
                .suTitle()
                .foregroundStyle(Color.suInkPrimary)
            Spacer()
        }
    }

    /// One column of the Pinterest grid. Each tile uses its image's natural aspect ratio.
    private func masonryColumn(items: [ReferenceLook]) -> some View {
        VStack(spacing: SUSpace.md) {
            ForEach(items) { ref in
                NavigationLink(value: ref) {
                    StoredImage(relativePath: ref.thumbnailPath, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.suSurfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: SURadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    ReferencesTabView()
        .modelContainer(for: ReferenceLook.self, inMemory: true)
}
