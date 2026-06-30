import SwiftUI
import SwiftData

struct ReferencesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReferenceLook.createdAt, order: .reverse) private var refs: [ReferenceLook]
    @State private var showingAdd = false

    private let cols = [
        GridItem(.flexible(), spacing: SUSpace.sm),
        GridItem(.flexible(), spacing: SUSpace.sm),
        GridItem(.flexible(), spacing: SUSpace.sm),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.suCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                            .padding(.horizontal, SUSpace.lg)
                            .padding(.top, SUSpace.md)
                            .padding(.bottom, SUSpace.lg)

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
                            LazyVGrid(columns: cols, spacing: SUSpace.sm) {
                                ForEach(refs) { ref in
                                    NavigationLink(value: ref) {
                                        StoredImage(relativePath: ref.thumbnailPath, contentMode: .fill)
                                            .aspectRatio(1, contentMode: .fit)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.suSurfaceMuted)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: SURadius.sm, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, SUSpace.lg)
                        }

                        Color.clear.frame(height: 100)
                    }
                }
                .navigationDestination(for: ReferenceLook.self) {
                    ReferenceDetailView(ref: $0)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAdd) {
                AddReferenceSheet()
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("References")
                .suTitle()
                .foregroundStyle(Color.suInkPrimary)
            Spacer()
        }
    }
}

#Preview {
    ReferencesTabView()
        .modelContainer(for: ReferenceLook.self, inMemory: true)
}
