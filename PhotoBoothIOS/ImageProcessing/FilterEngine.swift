import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Photo Filter Definition

/// A photo filter that transforms a CIImage using CoreImage.
///
/// Sendable + nonisolated so filters can be used from background threads.
struct PhotoFilter: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let iconName: String
    let apply: @Sendable (CIImage) -> CIImage

    nonisolated static func == (lhs: PhotoFilter, rhs: PhotoFilter) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Built-in Filters

nonisolated extension PhotoFilter {

    /// All available built-in filters.
    static let allFilters: [PhotoFilter] = [
        .natural, .vivid, .warm, .cool,
        .bwClassic, .bwHighContrast,
        .vintage, .chrome, .fade, .dramatic, .softGlow
    ]

    /// No filter — original photo.
    static let natural = PhotoFilter(
        id: "natural", name: "Natural", iconName: "photo"
    ) { image in image }

    /// Boosted color saturation.
    static let vivid = PhotoFilter(
        id: "vivid", name: "Vivid", iconName: "paintpalette"
    ) { image in
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = 1.3
        filter.contrast = 1.05
        return filter.outputImage ?? image
    }

    /// Warm golden tone.
    static let warm = PhotoFilter(
        id: "warm", name: "Warm", iconName: "sun.max"
    ) { image in
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: 6500 + 500, y: 0)
        return filter.outputImage ?? image
    }

    /// Cool blue tone.
    static let cool = PhotoFilter(
        id: "cool", name: "Cool", iconName: "snowflake"
    ) { image in
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: 6500 - 500, y: 0)
        return filter.outputImage ?? image
    }

    /// Classic black & white.
    static let bwClassic = PhotoFilter(
        id: "bw_classic", name: "B&W", iconName: "circle.lefthalf.filled"
    ) { image in
        let filter = CIFilter.photoEffectMono()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    /// High contrast black & white.
    static let bwHighContrast = PhotoFilter(
        id: "bw_noir", name: "Noir", iconName: "moon.fill"
    ) { image in
        let filter = CIFilter.photoEffectNoir()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    /// Faded vintage look.
    static let vintage = PhotoFilter(
        id: "vintage", name: "Vintage", iconName: "clock"
    ) { image in
        let filter = CIFilter.photoEffectTransfer()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    /// High contrast chrome.
    static let chrome = PhotoFilter(
        id: "chrome", name: "Chrome", iconName: "sparkles"
    ) { image in
        let filter = CIFilter.photoEffectChrome()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    /// Faded, low contrast.
    static let fade = PhotoFilter(
        id: "fade", name: "Fade", iconName: "aqi.low"
    ) { image in
        let filter = CIFilter.photoEffectFade()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    /// High drama — boosted contrast and shadows.
    static let dramatic = PhotoFilter(
        id: "dramatic", name: "Drama", iconName: "theatermasks"
    ) { image in
        let colorFilter = CIFilter.colorControls()
        colorFilter.inputImage = image
        colorFilter.contrast = 1.3
        colorFilter.saturation = 1.1
        guard let colorOutput = colorFilter.outputImage else { return image }

        let shadowFilter = CIFilter.highlightShadowAdjust()
        shadowFilter.inputImage = colorOutput
        shadowFilter.shadowAmount = 0.5
        shadowFilter.highlightAmount = 1.2
        return shadowFilter.outputImage ?? colorOutput
    }

    /// Dreamy soft glow.
    static let softGlow = PhotoFilter(
        id: "soft_glow", name: "Glow", iconName: "wand.and.stars"
    ) { image in
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = image
        blurFilter.radius = 15

        guard let blurred = blurFilter.outputImage else { return image }

        // Blend blurred on top with low opacity for glow effect
        let blendFilter = CIFilter.sourceOverCompositing()
        blendFilter.inputImage = blurred.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.3)
            ]
        )
        blendFilter.backgroundImage = image
        return blendFilter.outputImage ?? image
    }
}

// MARK: - Filter Engine

/// Applies filters to images using a shared Metal-backed CIContext.
///
/// Use the shared instance to avoid creating multiple expensive CIContexts.
/// Thread-safe — CIContext is safe to use from any thread.
final class FilterEngine: @unchecked Sendable {

    nonisolated static let shared = FilterEngine()

    /// Metal-backed CIContext — expensive to create, reuse across all filter operations.
    nonisolated let ciContext: CIContext

    nonisolated private init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
                .useSoftwareRenderer: false
            ])
        } else {
            ciContext = CIContext(options: [
                .useSoftwareRenderer: true
            ])
        }
    }

    /// Apply a filter to a UIImage and return the result.
    nonisolated func applyFilter(_ filter: PhotoFilter, to image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let filtered = filter.apply(ciImage)

        let extent = filtered.extent
        guard let cgImage = ciContext.createCGImage(filtered, from: extent) else { return image }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Generate a small thumbnail preview of a filter applied to an image.
    /// Resizes input first for fast thumbnail generation.
    nonisolated func generateThumbnail(
        _ filter: PhotoFilter,
        from image: UIImage,
        size: CGSize = CGSize(width: 80, height: 80)
    ) -> UIImage {
        // Downscale first for performance
        let thumbImage = image.preparingThumbnail(of: size) ?? image
        return applyFilter(filter, to: thumbImage)
    }

    /// Apply a filter to a CIImage (for live view pipeline).
    nonisolated func applyFilter(_ filter: PhotoFilter, to ciImage: CIImage) -> CIImage {
        filter.apply(ciImage)
    }

    /// Render a CIImage to UIImage using the shared context.
    nonisolated func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        let extent = ciImage.extent
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
