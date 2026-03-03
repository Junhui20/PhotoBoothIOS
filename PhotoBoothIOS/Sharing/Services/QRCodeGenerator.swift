import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Generates QR code UIImages from URL strings using CoreImage.
///
/// Uses nearest-neighbor scaling for crisp edges — QR codes must not be blurred.
/// All methods are nonisolated — safe to call from any context.
nonisolated enum QRCodeGenerator {

    /// Generate a QR code image for the given URL string.
    ///
    /// - Parameters:
    ///   - string: The text/URL to encode
    ///   - size: Desired output image size in points (default 300×300)
    /// - Returns: A UIImage of the QR code, or nil if generation fails
    static func generate(
        from string: String,
        size: CGSize = CGSize(width: 300, height: 300)
    ) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        // Generate raw QR code at native resolution (~33×33 for typical URLs)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"  // 15% error correction — good for URLs

        guard let rawOutput = filter.outputImage else { return nil }

        // Scale up using CIImage transform (nearest-neighbor, keeps pixels crisp)
        let scaleX = size.width / rawOutput.extent.width
        let scaleY = size.height / rawOutput.extent.height
        let scaled = rawOutput.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Render using the shared Metal-backed CIContext
        guard let cgImage = FilterEngine.shared.ciContext.createCGImage(
            scaled, from: scaled.extent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
