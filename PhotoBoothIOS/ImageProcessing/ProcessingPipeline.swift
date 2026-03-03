import CoreImage
import UIKit

// MARK: - Processed Output

/// The result of processing a photo through the pipeline.
struct ProcessedOutput {
    let displayImage: UIImage       // For on-screen review
    let printImage: UIImage         // High-res for printing (same as display for now)
    let shareImage: UIImage         // Optimized for digital sharing
    let thumbnailImage: UIImage     // Small thumbnail for gallery
}

// MARK: - Processing Pipeline

/// Orchestrates the full image processing chain:
/// Raw Photo → Filter → Background Removal → Overlays → Output
final class ProcessingPipeline {

    private let filterEngine = FilterEngine.shared
    private let overlayEngine = OverlayEngine()
    private let backgroundRemoval = BackgroundRemoval()

    /// Process a single photo through the full pipeline.
    ///
    /// - Parameters:
    ///   - photo: The raw captured photo
    ///   - filter: The filter to apply (use .natural for no filter)
    ///   - background: Background replacement (nil = keep original)
    ///   - overlays: Overlay elements to composite on top
    /// - Returns: ProcessedOutput with display, print, share, and thumbnail images
    func process(
        photo: CapturedPhoto,
        filter: PhotoFilter = .natural,
        background: BackgroundType? = nil,
        overlays: [OverlayElement] = []
    ) async throws -> ProcessedOutput {
        guard let originalImage = photo.uiImage else {
            throw ImageProcessingError.invalidInput
        }

        var processed = originalImage

        // Step 1: Apply filter
        if filter.id != "natural" {
            processed = filterEngine.applyFilter(filter, to: processed)
        }

        // Step 2: Background removal (if requested)
        if let bgType = background, !isOriginal(bgType) {
            processed = try await backgroundRemoval.removeBackground(
                from: processed,
                replacement: bgType
            )
        }

        // Step 3: Apply overlays
        if !overlays.isEmpty {
            processed = overlayEngine.composite(photo: processed, overlays: overlays)
        }

        // Generate output variants
        let displayImage = processed
        let printImage = processed
        let shareImage = resizeForSharing(processed, maxDimension: 1920)
        let thumbnailImage = processed.preparingThumbnail(of: CGSize(width: 200, height: 200)) ?? processed

        return ProcessedOutput(
            displayImage: displayImage,
            printImage: printImage,
            shareImage: shareImage,
            thumbnailImage: thumbnailImage
        )
    }

    /// Process multiple photos (for multi-photo layouts).
    func processMultiple(
        photos: [CapturedPhoto],
        filter: PhotoFilter = .natural,
        background: BackgroundType? = nil,
        overlays: [OverlayElement] = []
    ) async throws -> [ProcessedOutput] {
        var results: [ProcessedOutput] = []
        for photo in photos {
            let output = try await process(
                photo: photo,
                filter: filter,
                background: background,
                overlays: overlays
            )
            results.append(output)
        }
        return results
    }

    /// Quick filter-only processing (for filter preview thumbnails).
    func applyFilterOnly(to photo: CapturedPhoto, filter: PhotoFilter) -> UIImage? {
        guard let image = photo.uiImage else { return nil }
        if filter.id == "natural" { return image }
        return filterEngine.applyFilter(filter, to: image)
    }

    // MARK: - Private

    private func isOriginal(_ type: BackgroundType) -> Bool {
        if case .original = type { return true }
        return false
    }

    func resizeForSharing(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)

        if maxSide <= maxDimension { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        return image.preparingThumbnail(of: newSize) ?? image
    }
}
