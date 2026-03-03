import Foundation

/// Metadata for a saved photobooth session stored on disk.
///
/// File paths are derived by convention from the session `id`:
/// - Original: `sessions/{id}/original_{index}.jpg`
/// - Processed: `sessions/{id}/processed_{index}.jpg`
/// - Thumbnail: `sessions/{id}/thumb_{index}.jpg`
struct GallerySession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let photoCount: Int
    let filterName: String        // PhotoFilter.id ("natural", "vivid", etc.)
    let backgroundName: String    // BackgroundOption.name ("Original", "Blur", etc.)
}
