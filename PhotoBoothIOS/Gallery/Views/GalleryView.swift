import SwiftUI

/// Gallery grid showing all saved photobooth sessions — iOS Photos style.
///
/// Features: filter tabs (All / Today / This Week), date section headers,
/// 4-column grid with thumbnails, and bottom status bar.
struct GalleryView: View {

    @EnvironmentObject var galleryStore: GalleryStore
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteAllAlert = false
    @State private var activeFilter: GalleryFilter = .all

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if galleryStore.sessions.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        filterTabs
                            .padding(.top, 8)

                        sessionGrid

                        bottomStats
                    }
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        if !galleryStore.sessions.isEmpty {
                            Text("\(galleryStore.sessions.count) sessions")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.39, green: 0.4, blue: 0.95).opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.39, green: 0.4, blue: 0.95).opacity(0.12))
                                .cornerRadius(100)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if !galleryStore.sessions.isEmpty {
                            Button(action: { showDeleteAllAlert = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                    Text("Delete All")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(.red.opacity(0.8))
                            }
                        }

                        Button("Done") {
                            dismiss()
                        }
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

    // MARK: - Filter Tabs

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GalleryFilter.allCases) { filter in
                    Button(action: { activeFilter = filter }) {
                        Text(filter.label)
                            .font(.system(size: 13, weight: activeFilter == filter ? .semibold : .medium))
                            .foregroundColor(activeFilter == filter ? .white : .gray)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(activeFilter == filter ? Color(red: 0.39, green: 0.4, blue: 0.95) : Color.white.opacity(0.04))
                            .cornerRadius(100)
                    }
                }
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundColor(.white.opacity(0.2))
            Text("No Photos Yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Text("Completed sessions will appear here")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    // MARK: - Session Grid

    private var sessionGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: .sectionHeaders) {
                ForEach(groupedSections, id: \.title) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(section.sessions) { session in
                                NavigationLink(destination: GallerySessionDetailView(session: session)) {
                                    GalleryThumbnailCell(
                                        session: session,
                                        thumbnail: galleryStore.loadThumbnail(sessionID: session.id, index: 0)
                                    )
                                    .aspectRatio(1, contentMode: .fill)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        sectionHeader(title: section.title, count: section.sessions.count)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text("\(count) Photos")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.black)
    }

    // MARK: - Bottom Stats

    private var bottomStats: some View {
        HStack {
            Spacer()
            Text("\(filteredSessions.count) Sessions  \u{2022}  \(totalPhotoCount) Photos  \u{2022}  \(galleryStore.storageString)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
        .padding(.vertical, 12)
    }

    // MARK: - Data Grouping

    private var filteredSessions: [GallerySession] {
        let now = Date()
        let calendar = Calendar.current

        switch activeFilter {
        case .all:
            return galleryStore.sessions
        case .today:
            return galleryStore.sessions.filter { calendar.isDateInToday($0.timestamp) }
        case .thisWeek:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return galleryStore.sessions.filter { $0.timestamp >= weekAgo }
        }
    }

    private var totalPhotoCount: Int {
        filteredSessions.reduce(0) { $0 + $1.photoCount }
    }

    private var groupedSections: [GallerySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredSessions) { session -> String in
            if calendar.isDateInToday(session.timestamp) {
                return "Today"
            } else if calendar.isDateInYesterday(session.timestamp) {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: session.timestamp)
            }
        }

        return grouped
            .map { GallerySection(title: $0.key, sessions: $0.value) }
            .sorted { first, second in
                // "Today" first, "Yesterday" second, then by date descending
                let order = ["Today": 0, "Yesterday": 1]
                let firstOrder = order[first.title] ?? 2
                let secondOrder = order[second.title] ?? 2
                if firstOrder != secondOrder { return firstOrder < secondOrder }
                let firstDate = first.sessions.first?.timestamp ?? .distantPast
                let secondDate = second.sessions.first?.timestamp ?? .distantPast
                return firstDate > secondDate
            }
    }
}

// MARK: - Supporting Types

private struct GallerySection {
    let title: String
    let sessions: [GallerySession]
}

enum GalleryFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case thisWeek

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All Photos"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        }
    }
}
