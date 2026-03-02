import CoreImage
import UIKit
import Vision

// MARK: - Background Type

/// The replacement background after person segmentation.
enum BackgroundType {
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
final class BackgroundRemoval {

    private let ciContext: CIContext

    init(ciContext: CIContext? = nil) {
        self.ciContext = ciContext ?? FilterEngine.shared.ciContext
    }

    /// Generate a person segmentation mask from an image.
    ///
    /// - Parameters:
    ///   - image: The input photo as CIImage
    ///   - quality: Segmentation quality (.fast for preview, .accurate for final)
    /// - Returns: A grayscale mask CIImage (white = person, black = background)
    func generateMask(
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

                continuation.resume(returning: scaledMask)
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
    func removeBackground(
        from image: CIImage,
        replacement: BackgroundType,
        quality: VNGeneratePersonSegmentationRequest.QualityLevel = .accurate
    ) async throws -> CIImage {
        // If original, just return as-is
        if case .original = replacement { return image }

        let mask = try await generateMask(from: image, quality: quality)

        // Create the replacement background
        let background = createBackground(for: replacement, size: image.extent)

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
    func removeBackground(
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

    // MARK: - Private

    private func createBackground(for type: BackgroundType, size: CGRect) -> CIImage {
        switch type {
        case .original:
            return CIImage(color: .clear).cropped(to: size)

        case .solidColor(let uiColor):
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            let color = CIColor(red: r, green: g, blue: b, alpha: a)
            return CIImage(color: color).cropped(to: size)

        case .gradient(let topColor, let bottomColor):
            // Use a vertical gradient
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
            // Scale background image to fill the target size
            let scaleX = size.width / bgCI.extent.width
            let scaleY = size.height / bgCI.extent.height
            let scale = max(scaleX, scaleY)
            return bgCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: size)

        case .blurred:
            // This will be composited with the original image's blurred version
            // We return a placeholder; the caller should use the blurred original
            return CIImage(color: .black).cropped(to: size)

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
