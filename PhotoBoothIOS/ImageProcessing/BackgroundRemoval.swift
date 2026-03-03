import CoreImage
import UIKit
import Vision

// MARK: - Background Type

/// The replacement background after person segmentation.
///
/// Marked `@unchecked Sendable` because associated UIColor/UIImage values
/// are created once and never mutated after initialization.
enum BackgroundType: @unchecked Sendable {
    case original                       // No background removal
    case solidColor(UIColor)            // Solid color
    case gradient(UIColor, UIColor)     // Vertical gradient
    case image(UIImage)                 // Custom background image
    case blurred(radius: CGFloat)       // Blurred version of original
    case transparent                    // Transparent (for PNG export)
}

// MARK: - Background Removal

/// Removes or replaces photo backgrounds using Apple Vision person segmentation.
///
/// Uses `VNGeneratePersonSegmentationRequest` (iOS 15+).
/// Quality levels: `.fast` for preview, `.accurate` for final output.
/// Applies mask refinement (erode → dilate → feather) for smooth natural edges.
/// Thread-safe — all methods are nonisolated for background rendering.
final class BackgroundRemoval: @unchecked Sendable {

    nonisolated private let ciContext: CIContext

    nonisolated init(ciContext: CIContext? = nil) {
        self.ciContext = ciContext ?? FilterEngine.shared.ciContext
    }

    /// Generate a person segmentation mask from an image.
    ///
    /// - Parameters:
    ///   - image: The input photo as CIImage
    ///   - quality: Segmentation quality (.fast for preview, .accurate for final)
    /// - Returns: A refined grayscale mask CIImage (white = person, black = background)
    nonisolated func generateMask(
        from image: CIImage,
        quality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced
    ) async throws -> CIImage {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let result = request.results?.first,
                      let maskBuffer = result.pixelBuffer as CVPixelBuffer? else {
                    continuation.resume(throwing: ImageProcessingError.segmentationFailed)
                    return
                }

                let maskImage = CIImage(cvPixelBuffer: maskBuffer)

                // Scale mask to match original image size
                let scaleX = image.extent.width / maskImage.extent.width
                let scaleY = image.extent.height / maskImage.extent.height
                let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

                // Refine mask edges for natural-looking compositing
                let refined = refineMask(scaledMask, quality: quality, imageSize: image.extent.size)

                continuation.resume(returning: refined)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Remove or replace the background of a photo.
    ///
    /// - Parameters:
    ///   - image: The input photo as CIImage
    ///   - replacement: What to replace the background with
    ///   - quality: Segmentation quality
    /// - Returns: The composited result with new background
    nonisolated func removeBackground(
        from image: CIImage,
        replacement: BackgroundType,
        quality: VNGeneratePersonSegmentationRequest.QualityLevel = .accurate
    ) async throws -> CIImage {
        // If original, just return as-is
        if case .original = replacement { return image }

        let mask = try await generateMask(from: image, quality: quality)

        // Create the replacement background (pass original for .blurred case)
        let background = createBackground(for: replacement, size: image.extent, originalImage: image)

        // Composite: person (masked from original) over new background
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = image
        blendFilter.backgroundImage = background
        blendFilter.maskImage = mask

        guard let output = blendFilter.outputImage else {
            throw ImageProcessingError.compositingFailed
        }

        return output
    }

    /// Remove background and return a UIImage.
    nonisolated func removeBackground(
        from photo: UIImage,
        replacement: BackgroundType,
        quality: VNGeneratePersonSegmentationRequest.QualityLevel = .accurate
    ) async throws -> UIImage {
        guard let ciImage = CIImage(image: photo) else {
            throw ImageProcessingError.invalidInput
        }

        let result = try await removeBackground(from: ciImage, replacement: replacement, quality: quality)

        guard let cgImage = ciContext.createCGImage(result, from: result.extent) else {
            throw ImageProcessingError.renderFailed
        }

        return UIImage(cgImage: cgImage, scale: photo.scale, orientation: photo.imageOrientation)
    }

    // MARK: - Mask Refinement

    /// Refine segmentation mask with morphological operations and feathering.
    ///
    /// Pipeline: erode → dilate → median denoise → Gaussian feather.
    /// Feathering radius scales with image resolution for consistent results across sizes.
    nonisolated private func refineMask(
        _ mask: CIImage,
        quality: VNGeneratePersonSegmentationRequest.QualityLevel,
        imageSize: CGSize
    ) -> CIImage {
        let maxDimension = max(imageSize.width, imageSize.height)
        var refined = mask

        switch quality {
        case .fast:
            // Thumbnails: feathering only (morphology too expensive for tiny images)
            let featherRadius = max(1.0, maxDimension * 0.003)
            refined = applyGaussianBlur(to: refined, radius: featherRadius)

        case .balanced:
            // Review preview: light morphology + feathering
            let erodeRadius = max(0.5, maxDimension * 0.0004)
            let dilateRadius = max(0.3, maxDimension * 0.00025)
            let featherRadius = max(1.5, maxDimension * 0.0025)

            refined = applyMorphologyMinimum(to: refined, radius: erodeRadius)
            refined = applyMorphologyMaximum(to: refined, radius: dilateRadius)
            refined = applyGaussianBlur(to: refined, radius: featherRadius)

        case .accurate:
            // Final output: full pipeline
            let erodeRadius = max(0.5, maxDimension * 0.0003)
            let dilateRadius = max(0.3, maxDimension * 0.0002)
            let featherRadius = max(1.5, maxDimension * 0.002)

            refined = applyMorphologyMinimum(to: refined, radius: erodeRadius)
            refined = applyMorphologyMaximum(to: refined, radius: dilateRadius)
            refined = applyMedianFilter(to: refined)
            refined = applyGaussianBlur(to: refined, radius: featherRadius)

        @unknown default:
            let featherRadius = max(1.5, maxDimension * 0.002)
            refined = applyGaussianBlur(to: refined, radius: featherRadius)
        }

        return refined
    }

    // MARK: - CIFilter Helpers

    nonisolated private func applyGaussianBlur(to image: CIImage, radius: CGFloat) -> CIImage {
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = image
        filter.radius = Float(radius)
        // Clamp to avoid edge darkening from blur extending past image bounds
        return filter.outputImage?.clamped(to: image.extent) ?? image
    }

    nonisolated private func applyMorphologyMinimum(to image: CIImage, radius: CGFloat) -> CIImage {
        let filter = CIFilter.morphologyMinimum()
        filter.inputImage = image
        filter.radius = Float(radius)
        return filter.outputImage ?? image
    }

    nonisolated private func applyMorphologyMaximum(to image: CIImage, radius: CGFloat) -> CIImage {
        let filter = CIFilter.morphologyMaximum()
        filter.inputImage = image
        filter.radius = Float(radius)
        return filter.outputImage ?? image
    }

    nonisolated private func applyMedianFilter(to image: CIImage) -> CIImage {
        let filter = CIFilter.medianFilter()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    // MARK: - Background Creation

    nonisolated private func createBackground(
        for type: BackgroundType,
        size: CGRect,
        originalImage: CIImage? = nil
    ) -> CIImage {
        switch type {
        case .original:
            return CIImage(color: .clear).cropped(to: size)

        case .solidColor(let uiColor):
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            let color = CIColor(red: r, green: g, blue: b, alpha: a)
            return CIImage(color: color).cropped(to: size)

        case .gradient(let topColor, let bottomColor):
            let gradientFilter = CIFilter.linearGradient()
            gradientFilter.point0 = CGPoint(x: size.midX, y: size.minY)
            gradientFilter.point1 = CGPoint(x: size.midX, y: size.maxY)

            var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
            bottomColor.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
            gradientFilter.color0 = CIColor(red: r0, green: g0, blue: b0)

            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            topColor.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            gradientFilter.color1 = CIColor(red: r1, green: g1, blue: b1)

            return gradientFilter.outputImage?.cropped(to: size) ?? CIImage(color: .black).cropped(to: size)

        case .image(let bgImage):
            guard let bgCI = CIImage(image: bgImage) else {
                return CIImage(color: .black).cropped(to: size)
            }
            let scaleX = size.width / bgCI.extent.width
            let scaleY = size.height / bgCI.extent.height
            let scale = max(scaleX, scaleY)
            return bgCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: size)

        case .blurred(let radius):
            guard let original = originalImage else {
                return CIImage(color: .black).cropped(to: size)
            }
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = original
            blur.radius = Float(radius)
            return blur.outputImage?
                .clamped(to: original.extent)
                .cropped(to: size)
                ?? CIImage(color: .black).cropped(to: size)

        case .transparent:
            return CIImage(color: .clear).cropped(to: size)
        }
    }
}

// MARK: - Errors

enum ImageProcessingError: LocalizedError {
    case invalidInput
    case segmentationFailed
    case compositingFailed
    case renderFailed
    case filterFailed

    var errorDescription: String? {
        switch self {
        case .invalidInput:        return "Invalid input image."
        case .segmentationFailed:  return "Person segmentation failed."
        case .compositingFailed:   return "Image compositing failed."
        case .renderFailed:        return "Failed to render processed image."
        case .filterFailed:        return "Filter application failed."
        }
    }
}
