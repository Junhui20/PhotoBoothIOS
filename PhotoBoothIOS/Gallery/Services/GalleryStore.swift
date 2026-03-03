import Combine
import Foundation
import UIKit
import os

/// Manages persistent storage and retrieval of photobooth sessions.
///
/// Storage layout under App Documents/:
/// ```
/// Gallery/
/// ├── index.json
/// └── sessions/{uuid}/
///     ├── original_0.jpg
///     ├── processed_0.jpg
///     └── thumb_0.jpg
/// ```
///
/// Thread model:
/// - `@Published` properties on MainActor (default)
/// - File I/O in `Task.detached` to keep UI responsive
/// - Path helpers and image loading are `nonisolated` (FileManager is thread-safe)
/// - JSON writes are atomic (write temp → rename)
final class GalleryStore: ObservableObject {

    // MARK: - Published

    @Published var sessions: [GallerySession] = []
    @Published var storageString: String = ""

    // MARK: - Private

    private nonisolated let logger = Logger(
        subsystem: "com.photobooth.gallery", category: "GalleryStore"
    )

    /// In-memory thumbnail cache (thread-safe).
    private nonisolated let thumbnailCache = NSCache<NSString, UIImage>()

    // MARK: - Shared Encoder/Decoder (nonisolated, thread-safe after init)

    private nonisolated static let sharedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private nonisolated static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Paths (nonisolated — FileManager is thread-safe)

    private nonisolated var galleryRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Gallery", isDirectory: true)
    }

    private nonisolated var sessionsRoot: URL {
        galleryRoot.appendingPathComponent("sessions", isDirectory: true)
    }

    private nonisolated var indexFileURL: URL {
        galleryRoot.appendingPathComponent("index.json")
    }

    nonisolated func sessionDirectory(for id: UUID) -> URL {
        sessionsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    // MARK: - Init

    init() {
        ensureDirectories()
        thumbnailCache.countLimit = 200
    }

    // MARK: - Public API

    /// Load all sessions from the index file on disk.
    func loadSessions() {
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: self.indexFileURL)
                let loaded = try Self.sharedDecoder.decode([GallerySession].self, from: data)
                let sorted = loaded.sorted { $0.timestamp > $1.timestamp }
                await MainActor.run {
                    self.sessions = sorted
                }
                self.logger.info("Loaded \(sorted.count) sessions from index")
            } catch {
                self.logger.info("No gallery index found (first launch or empty): \(error.localizedDescription)")
            }

            // Also compute storage size
            let size = self.computeStorageUsed()
            await MainActor.run {
                self.storageString = size
            }
        }
    }

    /// Save a complete session to disk (photos + metadata).
    ///
    /// Called from `SessionViewModel.acceptPhotos()`. Runs file I/O on a background thread.
    func saveSession(
        photos: [CapturedPhoto],
        processedImages: [UIImage],
        shareImages: [UIImage],
        filter: PhotoFilter,
        background: BackgroundOption
    ) async {
        let sessionID = UUID()
        let timestamp = Date()
        let photoCount = photos.count
        let filterName = filter.id
        let backgroundName = background.name

        let sessionDir = sessionDirectory(for: sessionID)
        let lgr = logger

        // Write files on background thread
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

                for (index, photo) in photos.enumerated() {
                    // Original JPEG from camera
                    let originalURL = sessionDir.appendingPathComponent("original_\(index).jpg")
                    try photo.imageData.write(to: originalURL)

                    // Processed image (share-quality 1920px)
                    if index < shareImages.count {
                        let processedURL = sessionDir.appendingPathComponent("processed_\(index).jpg")
                        if let jpegData = shareImages[index].jpegData(compressionQuality: 0.88) {
                            try jpegData.write(to: processedURL)
                        }
                    } else if index < processedImages.count {
                        let processedURL = sessionDir.appendingPathComponent("processed_\(index).jpg")
                        if let jpegData = processedImages[index].jpegData(compressionQuality: 0.88) {
                            try jpegData.write(to: processedURL)
                        }
                    }

                    // Thumbnail (200x200)
                    let thumbURL = sessionDir.appendingPathComponent("thumb_\(index).jpg")
                    let sourceImage: UIImage? = (index < shareImages.count) ? shareImages[index]
                        : (index < processedImages.count) ? processedImages[index]
                        : photo.uiImage
                    if let source = sourceImage,
                       let thumb = source.preparingThumbnail(of: CGSize(width: 200, height: 200)),
                       let thumbData = thumb.jpegData(compressionQuality: 0.75) {
                        try thumbData.write(to: thumbURL)
                    }
                }

                lgr.info("Saved \(photoCount) photos for session \(sessionID)")
            } catch {
                lgr.error("Failed to save session files: \(error)")
            }
        }.value

        // Create session metadata and update index
        let session = GallerySession(
            id: sessionID,
            timestamp: timestamp,
            photoCount: photoCount,
            filterName: filterName,
            backgroundName: backgroundName
        )

        var updated = sessions
        updated.insert(session, at: 0) // newest first
        sessions = updated

        // Write index on background
        let indexURL = indexFileURL
        let galleryDir = galleryRoot
        await Task.detached(priority: .utility) {
            Self.writeIndexToDisk(sessions: updated, indexURL: indexURL, galleryDir: galleryDir)
        }.value

        // Update storage size
        Task.detached { [weak self] in
            guard let self else { return }
            let size = self.computeStorageUsed()
            await MainActor.run { self.storageString = size }
        }

        logger.info("Session \(sessionID) saved to gallery")
    }

    // MARK: - Image Loading (nonisolated — safe from any thread)

    /// Load a thumbnail image for the gallery grid. Uses NSCache.
    nonisolated func loadThumbnail(sessionID: UUID, index: Int) -> UIImage? {
        let cacheKey = "\(sessionID)-thumb-\(index)" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        let url = sessionDirectory(for: sessionID)
            .appendingPathComponent("thumb_\(index).jpg")
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        thumbnailCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Load a processed (share-quality) image for detail view or re-sharing.
    nonisolated func loadProcessedImage(sessionID: UUID, index: Int) -> UIImage? {
        let url = sessionDirectory(for: sessionID)
            .appendingPathComponent("processed_\(index).jpg")
        return UIImage(contentsOfFile: url.path)
    }

    /// Load the original camera JPEG.
    nonisolated func loadOriginalImage(sessionID: UUID, index: Int) -> UIImage? {
        let url = sessionDirectory(for: sessionID)
            .appendingPathComponent("original_\(index).jpg")
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Delete

    /// Delete a single session and its files.
    func deleteSession(_ session: GallerySession) {
        let dir = sessionDirectory(for: session.id)
        let lgr = logger

        // Remove from in-memory list
        sessions.removeAll { $0.id == session.id }

        // Clear thumbnail cache entries
        for i in 0..<session.photoCount {
            thumbnailCache.removeObject(forKey: "\(session.id)-thumb-\(i)" as NSString)
        }

        // Remove files and update index on background
        let updatedSessions = sessions
        let indexURL = indexFileURL
        let galleryDir = galleryRoot

        Task.detached {
            do {
                if FileManager.default.fileExists(atPath: dir.path) {
                    try FileManager.default.removeItem(at: dir)
                }
                lgr.info("Deleted session directory: \(session.id)")
            } catch {
                lgr.error("Failed to delete session \(session.id): \(error)")
            }
            Self.writeIndexToDisk(sessions: updatedSessions, indexURL: indexURL, galleryDir: galleryDir)
        }
    }

    /// Delete all sessions and clear the gallery.
    func deleteAllSessions() {
        let root = sessionsRoot
        let lgr = logger
        let indexURL = indexFileURL
        let galleryDir = galleryRoot

        sessions = []
        thumbnailCache.removeAllObjects()
        storageString = "0 MB"

        Task.detached {
            do {
                if FileManager.default.fileExists(atPath: root.path) {
                    try FileManager.default.removeItem(at: root)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                }
                lgr.info("Deleted all sessions")
            } catch {
                lgr.error("Failed to delete all sessions: \(error)")
            }
            Self.writeIndexToDisk(sessions: [], indexURL: indexURL, galleryDir: galleryDir)
        }
    }

    // MARK: - Storage Info

    /// Compute total storage used by the gallery (synchronous, call from background).
    private nonisolated func computeStorageUsed() -> String {
        let root = galleryRoot
        guard FileManager.default.fileExists(atPath: root.path) else { return "0 MB" }

        var totalBytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = values.fileSize {
                    totalBytes += Int64(size)
                }
            }
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }

    // MARK: - Private Helpers

    private func ensureDirectories() {
        do {
            try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create gallery directories: \(error)")
        }
    }

    /// Atomically write the session index to disk (temp file → rename).
    /// Static + nonisolated — safe to call from any thread with pre-captured URLs.
    private nonisolated static func writeIndexToDisk(
        sessions: [GallerySession],
        indexURL: URL,
        galleryDir: URL
    ) {
        do {
            let data = try sharedEncoder.encode(sessions)
            let tempURL = galleryDir.appendingPathComponent("index.tmp.json")
            try data.write(to: tempURL, options: .atomic)

            if FileManager.default.fileExists(atPath: indexURL.path) {
                try FileManager.default.removeItem(at: indexURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: indexURL)
        } catch {
            Logger(subsystem: "com.photobooth.gallery", category: "GalleryStore")
                .error("Failed to write index: \(error)")
        }
    }
}
