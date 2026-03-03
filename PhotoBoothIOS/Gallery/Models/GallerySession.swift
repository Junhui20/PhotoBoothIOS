import Foundation

/// Metadata for a saved photobooth session stored on disk.
///
/// File paths are derived by convention from the session `id`:
/// - Original: `sessions/{id}/original_{index}.jpg`
/// - Processed: `sessions/{id}/processed_{index}.jpg`
/// - Thumbnail: `sessions/{id}/thumb_{index}.jpg`
/// - GIF: `sessions/{id}/animation.gif` (when `hasGIF == true`)
struct GallerySession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let photoCount: Int
    let filterName: String        // PhotoFilter.id ("natural", "vivid", etc.)
    let backgroundName: String    // BackgroundOption.name ("Original", "Blur", etc.)
    let captureMode: String       // CaptureMode raw value ("photo", "boomerangGIF", "burstGIF")
    let hasGIF: Bool              // True if session has animation.gif on disk

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        photoCount: Int,
        filterName: String,
        backgroundName: String,
        captureMode: String = "photo",
        hasGIF: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.photoCount = photoCount
        self.filterName = filterName
        self.backgroundName = backgroundName
        self.captureMode = captureMode
        self.hasGIF = hasGIF
    }

    // Custom decoder for backward compatibility — old sessions don't have captureMode/hasGIF
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        photoCount = try container.decode(Int.self, forKey: .photoCount)
        filterName = try container.decode(String.self, forKey: .filterName)
        backgroundName = try container.decode(String.self, forKey: .backgroundName)
        captureMode = try container.decodeIfPresent(String.self, forKey: .captureMode) ?? "photo"
        hasGIF = try container.decodeIfPresent(Bool.self, forKey: .hasGIF) ?? false
    }
}
