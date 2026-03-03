import SwiftUI

/// Gallery grid showing all saved photobooth sessions.
///
/// Presented as a sheet from the attract screen. Shows a LazyVGrid
/// of session thumbnails with navigation to session detail.
struct GalleryView: View {

    @EnvironmentObject var galleryStore: GalleryStore
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteAllAlert = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if galleryStore.sessions.isEmpty {
                    emptyState
                } else {
                    sessionGrid
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !galleryStore.sessions.isEmpty {
                        Button("Delete All") {
                            showDeleteAllAlert = true
                        }
                        .foregroundColor(.red)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Text("\(galleryStore.sessions.count) sessions")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(galleryStore.storageString)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .alert("Delete All Sessions?", isPresented: $showDeleteAllAlert) {
                Button("Delete All", role: .destructive) {
                    galleryStore.deleteAllSessions()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(galleryStore.sessions.count) sessions and their photos. This cannot be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundColor(.white.opacity(0.2))
            Text("No Photos Yet")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white.opacity(0.5))
            Text("Completed sessions will appear here")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.3))
        }
    }

    // MARK: - Session Grid

    private var sessionGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(galleryStore.sessions) { session in
                    NavigationLink(destination: GallerySessionDetailView(session: session)) {
                        GalleryThumbnailCell(
                            session: session,
                            thumbnail: galleryStore.loadThumbnail(sessionID: session.id, index: 0)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}
