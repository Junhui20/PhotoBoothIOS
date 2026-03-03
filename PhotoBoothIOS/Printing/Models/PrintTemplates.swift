import CoreGraphics
import Foundation

// MARK: - Built-in Print Templates

/// Pre-built print layout templates.
///
/// All coordinates are normalized 0-1 relative to the safe area.
/// Templates are Swift structs for compile-time safety (no JSON parsing).
enum PrintTemplates {

    /// All available templates.
    static let all: [PrintLayout] = [
        classicStrip, photoCard, grid, duplicateStrip, postcard
    ]

    // MARK: - Classic Strip (2×6)

    /// 3 photos stacked vertically with event name at bottom.
    static let classicStrip = PrintLayout(
        id: "classic_strip",
        name: "Classic Strip",
        iconName: "rectangle.split.3x1",
        paperSize: .size2x6,
        orientation: .portrait,
        photoSlots: [
            PhotoSlot(id: 0, rect: CGRect(x: 0.03, y: 0.02, width: 0.94, height: 0.28),
                      cornerRadius: 0.02, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            PhotoSlot(id: 1, rect: CGRect(x: 0.03, y: 0.32, width: 0.94, height: 0.28),
                      cornerRadius: 0.02, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            PhotoSlot(id: 2, rect: CGRect(x: 0.03, y: 0.62, width: 0.94, height: 0.28),
                      cornerRadius: 0.02, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
        ],
        textZones: [
            TextZone(id: "eventName",
                     rect: CGRect(x: 0.05, y: 0.92, width: 0.9, height: 0.06),
                     defaultText: "PhotoBooth Pro",
                     fontName: "Helvetica-Bold", fontSizeRatio: 0.028,
                     colorHex: "#333333", alignment: .center, maxLines: 1),
        ],
        background: .white,
        bleedInches: 0.125,
        safeMarginInches: 0.0625,
        requiredPhotoCount: 3
    )

    // MARK: - Photo Card (4×6)

    /// Single large photo with event name at top, date at bottom.
    static let photoCard = PrintLayout(
        id: "photo_card",
        name: "Photo Card",
        iconName: "rectangle.portrait",
        paperSize: .size4x6,
        orientation: .portrait,
        photoSlots: [
            PhotoSlot(id: 0, rect: CGRect(x: 0.05, y: 0.10, width: 0.9, height: 0.75),
                      cornerRadius: 0.01, borderWidth: 2, borderColorHex: "#DDDDDD",
                      rotation: 0, aspectFill: true),
        ],
        textZones: [
            TextZone(id: "eventName",
                     rect: CGRect(x: 0.05, y: 0.02, width: 0.9, height: 0.06),
                     defaultText: "PhotoBooth Pro",
                     fontName: "Helvetica-Bold", fontSizeRatio: 0.03,
                     colorHex: "#333333", alignment: .center, maxLines: 1),
            TextZone(id: "date",
                     rect: CGRect(x: 0.05, y: 0.88, width: 0.9, height: 0.05),
                     defaultText: "",
                     fontName: "Helvetica", fontSizeRatio: 0.022,
                     colorHex: "#666666", alignment: .center, maxLines: 1),
        ],
        background: .white,
        bleedInches: 0.125,
        safeMarginInches: 0.125,
        requiredPhotoCount: 1
    )

    // MARK: - Grid (4×6)

    /// 4 photos in 2×2 grid with branding at bottom.
    static let grid = PrintLayout(
        id: "grid_4x6",
        name: "Grid",
        iconName: "square.grid.2x2",
        paperSize: .size4x6,
        orientation: .portrait,
        photoSlots: [
            PhotoSlot(id: 0, rect: CGRect(x: 0.02, y: 0.02, width: 0.47, height: 0.42),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            PhotoSlot(id: 1, rect: CGRect(x: 0.51, y: 0.02, width: 0.47, height: 0.42),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            PhotoSlot(id: 2, rect: CGRect(x: 0.02, y: 0.46, width: 0.47, height: 0.42),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            PhotoSlot(id: 3, rect: CGRect(x: 0.51, y: 0.46, width: 0.47, height: 0.42),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
        ],
        textZones: [
            TextZone(id: "eventName",
                     rect: CGRect(x: 0.05, y: 0.90, width: 0.9, height: 0.06),
                     defaultText: "PhotoBooth Pro",
                     fontName: "Helvetica-Bold", fontSizeRatio: 0.025,
                     colorHex: "#333333", alignment: .center, maxLines: 1),
        ],
        background: .white,
        bleedInches: 0.125,
        safeMarginInches: 0.125,
        requiredPhotoCount: 4
    )

    // MARK: - Duplicate Strip (4×6)

    /// Two identical 2×6 strips side-by-side on one 4×6 card.
    /// Left strip: slots 0-2, Right strip: slots 3-5 (same photos, mirrored).
    /// Designed to be cut apart — renderer draws a dotted cut line.
    static let duplicateStrip = PrintLayout(
        id: "duplicate_strip",
        name: "Double Strip",
        iconName: "rectangle.split.2x1",
        paperSize: .size4x6,
        orientation: .portrait,
        photoSlots: [
            // Left strip
            PhotoSlot(id: 0, rect: CGRect(x: 0.02, y: 0.02, width: 0.46, height: 0.28),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            PhotoSlot(id: 1, rect: CGRect(x: 0.02, y: 0.32, width: 0.46, height: 0.28),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            PhotoSlot(id: 2, rect: CGRect(x: 0.02, y: 0.62, width: 0.46, height: 0.28),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            // Right strip (same photos)
            PhotoSlot(id: 3, rect: CGRect(x: 0.52, y: 0.02, width: 0.46, height: 0.28),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            PhotoSlot(id: 4, rect: CGRect(x: 0.52, y: 0.32, width: 0.46, height: 0.28),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
            PhotoSlot(id: 5, rect: CGRect(x: 0.52, y: 0.62, width: 0.46, height: 0.28),
                      cornerRadius: 0.01, borderWidth: 0, borderColorHex: "#FFFFFF",
                      rotation: 0, aspectFill: true),
        ],
        textZones: [
            // Left strip text
            TextZone(id: "eventName",
                     rect: CGRect(x: 0.02, y: 0.92, width: 0.46, height: 0.06),
                     defaultText: "PhotoBooth Pro",
                     fontName: "Helvetica-Bold", fontSizeRatio: 0.02,
                     colorHex: "#333333", alignment: .center, maxLines: 1),
            // Right strip text (same)
            TextZone(id: "eventName_right",
                     rect: CGRect(x: 0.52, y: 0.92, width: 0.46, height: 0.06),
                     defaultText: "PhotoBooth Pro",
                     fontName: "Helvetica-Bold", fontSizeRatio: 0.02,
                     colorHex: "#333333", alignment: .center, maxLines: 1),
        ],
        background: .white,
        bleedInches: 0.125,
        safeMarginInches: 0.0625,
        requiredPhotoCount: 3
    )

    // MARK: - Postcard (4×6 Landscape)

    /// Landscape postcard — photo on left, text/branding on right.
    static let postcard = PrintLayout(
        id: "postcard",
        name: "Postcard",
        iconName: "envelope",
        paperSize: .size4x6,
        orientation: .landscape,
        photoSlots: [
            PhotoSlot(id: 0, rect: CGRect(x: 0.02, y: 0.04, width: 0.48, height: 0.92),
                      cornerRadius: 0.01, borderWidth: 1, borderColorHex: "#CCCCCC",
                      rotation: 0, aspectFill: true),
        ],
        textZones: [
            TextZone(id: "eventName",
                     rect: CGRect(x: 0.55, y: 0.10, width: 0.40, height: 0.15),
                     defaultText: "PhotoBooth Pro",
                     fontName: "Helvetica-Bold", fontSizeRatio: 0.04,
                     colorHex: "#333333", alignment: .center, maxLines: 2),
            TextZone(id: "message",
                     rect: CGRect(x: 0.55, y: 0.35, width: 0.40, height: 0.30),
                     defaultText: "Wish you were here!",
                     fontName: "Helvetica", fontSizeRatio: 0.025,
                     colorHex: "#555555", alignment: .center, maxLines: 4),
            TextZone(id: "date",
                     rect: CGRect(x: 0.55, y: 0.80, width: 0.40, height: 0.10),
                     defaultText: "",
                     fontName: "Helvetica-Light", fontSizeRatio: 0.02,
                     colorHex: "#888888", alignment: .center, maxLines: 1),
        ],
        background: .solidColor(hex: "#F5F5F0"),
        bleedInches: 0.125,
        safeMarginInches: 0.125,
        requiredPhotoCount: 1
    )

    // MARK: - Template Lookup

    /// Find the best matching template for a given layout mode.
    static func templateFor(layoutMode: LayoutMode) -> PrintLayout {
        switch layoutMode {
        case .single: return photoCard
        case .duo:    return photoCard  // Use photo card for 2 photos (print first)
        case .strip:  return classicStrip
        case .grid4:  return grid
        }
    }
}
