import CoreGraphics
import UIKit

// MARK: - Paper Size

/// Physical paper sizes with dimensions in inches.
enum PaperSize: String, CaseIterable, Sendable {
    case size2x6    // Photo strip
    case size4x6    // Standard photo print
    case size5x7
    case sizeA4
    case sizeLetter

    var widthInches: CGFloat {
        switch self {
        case .size2x6:    return 2.0
        case .size4x6:    return 4.0
        case .size5x7:    return 5.0
        case .sizeA4:     return 8.27
        case .sizeLetter: return 8.5
        }
    }

    var heightInches: CGFloat {
        switch self {
        case .size2x6:    return 6.0
        case .size4x6:    return 6.0
        case .size5x7:    return 7.0
        case .sizeA4:     return 11.69
        case .sizeLetter: return 11.0
        }
    }

    var displayName: String {
        switch self {
        case .size2x6:    return "2×6 Strip"
        case .size4x6:    return "4×6 Photo"
        case .size5x7:    return "5×7 Photo"
        case .sizeA4:     return "A4"
        case .sizeLetter: return "Letter"
        }
    }

    /// Pixel dimensions at given DPI.
    func pixelSize(dpi: Int) -> CGSize {
        CGSize(
            width: CGFloat(dpi) * widthInches,
            height: CGFloat(dpi) * heightInches
        )
    }
}

// MARK: - Print Orientation

enum PrintOrientation: String, Sendable {
    case portrait
    case landscape
}

// MARK: - Photo Slot

/// A rectangular region where a photo is placed in the layout.
///
/// All coordinates are normalized 0-1 relative to the safe area.
struct PhotoSlot: Identifiable, Sendable {
    let id: Int
    let rect: CGRect                // Normalized position/size
    let cornerRadius: CGFloat       // As fraction of min(width, height)
    let borderWidth: CGFloat        // In points at 300 DPI
    let borderColorHex: String
    let rotation: Double            // Degrees
    let aspectFill: Bool            // true = crop to fill, false = fit with letterbox
}

// MARK: - Text Zone

/// A text region with token replacement support.
///
/// Token ids like "eventName", "date", "hashtag" are replaced with actual values at render time.
struct TextZone: Identifiable, Sendable {
    let id: String
    let rect: CGRect                // Normalized position/size
    let defaultText: String
    let fontName: String
    let fontSizeRatio: CGFloat      // Font size as ratio of canvas height
    let colorHex: String
    let alignment: NSTextAlignment
    let maxLines: Int
}

// MARK: - Background

/// The background fill for a print layout.
enum PrintBackground: Sendable {
    case white
    case solidColor(hex: String)
    case gradient(topHex: String, bottomHex: String)
}

// MARK: - Print Layout

/// A complete print layout template.
///
/// All photo/text positions use normalized 0-1 coordinates so templates
/// render correctly at any DPI (72 for preview, 300 for print).
struct PrintLayout: Identifiable, Sendable {
    let id: String
    let name: String
    let iconName: String
    let paperSize: PaperSize
    let orientation: PrintOrientation
    let photoSlots: [PhotoSlot]
    let textZones: [TextZone]
    let background: PrintBackground
    let bleedInches: CGFloat
    let safeMarginInches: CGFloat
    let requiredPhotoCount: Int

    /// Full canvas size in pixels (paper + bleed on all sides).
    func canvasPixelSize(dpi: Int) -> CGSize {
        let totalBleed = bleedInches * 2
        let w: CGFloat
        let h: CGFloat

        switch orientation {
        case .portrait:
            w = (paperSize.widthInches + totalBleed) * CGFloat(dpi)
            h = (paperSize.heightInches + totalBleed) * CGFloat(dpi)
        case .landscape:
            w = (paperSize.heightInches + totalBleed) * CGFloat(dpi)
            h = (paperSize.widthInches + totalBleed) * CGFloat(dpi)
        }
        return CGSize(width: w, height: h)
    }

    /// Safe area rect in pixels (inside bleed + safe margin).
    func safeAreaRect(dpi: Int) -> CGRect {
        let canvas = canvasPixelSize(dpi: dpi)
        let inset = (bleedInches + safeMarginInches) * CGFloat(dpi)
        return CGRect(
            x: inset,
            y: inset,
            width: canvas.width - inset * 2,
            height: canvas.height - inset * 2
        )
    }
}
