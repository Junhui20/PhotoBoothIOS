import CoreGraphics
import UIKit

// MARK: - Overlay Element Model

/// A graphical element composited on top of or behind a photo.
struct OverlayElement: Identifiable, Codable {
    let id: UUID
    var type: OverlayType
    var position: CGPoint    // Normalized 0-1 within the canvas
    var size: CGSize         // Normalized 0-1 within the canvas
    var rotation: Double     // Degrees
    var opacity: Double      // 0-1
    var zIndex: Int          // Render order (lower = behind)

    init(
        type: OverlayType,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        size: CGSize = CGSize(width: 0.2, height: 0.2),
        rotation: Double = 0,
        opacity: Double = 1.0,
        zIndex: Int = 0
    ) {
        self.id = UUID()
        self.type = type
        self.position = position
        self.size = size
        self.rotation = rotation
        self.opacity = opacity
        self.zIndex = zIndex
    }
}

/// Types of overlays that can be composited.
enum OverlayType: Codable {
    case frame(imageName: String)       // PNG with transparent center
    case logo(imageName: String)        // Brand/event logo
    case text(TextOverlay)              // Custom text
    case border(BorderOverlay)          // Solid color/gradient border
    case watermark(text: String)        // Semi-transparent watermark
}

/// Configuration for a text overlay.
struct TextOverlay: Codable {
    var content: String
    var fontName: String = "Helvetica-Bold"
    var fontSize: CGFloat = 24
    var colorHex: String = "#FFFFFF"
}

/// Configuration for a border overlay.
struct BorderOverlay: Codable {
    var colorHex: String = "#FFFFFF"
    var width: CGFloat = 20
    var cornerRadius: CGFloat = 0
}

// MARK: - Overlay Engine

/// Composites overlay elements onto a photo using CoreGraphics.
final class OverlayEngine {

    /// Composite overlays onto a base photo image.
    ///
    /// - Parameters:
    ///   - photo: The base photo to composite onto
    ///   - overlays: Overlay elements sorted by zIndex
    /// - Returns: The composited image
    func composite(photo: UIImage, overlays: [OverlayElement]) -> UIImage {
        let canvasSize = photo.size
        let sortedOverlays = overlays.sorted { $0.zIndex < $1.zIndex }

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            // Draw base photo
            photo.draw(in: CGRect(origin: .zero, size: canvasSize))

            // Draw each overlay
            for overlay in sortedOverlays {
                drawOverlay(overlay, in: context, canvasSize: canvasSize)
            }
        }
    }

    /// Add a simple border to a photo.
    func addBorder(to photo: UIImage, color: UIColor, width: CGFloat, cornerRadius: CGFloat = 0) -> UIImage {
        let borderSize = CGSize(
            width: photo.size.width + width * 2,
            height: photo.size.height + width * 2
        )

        let renderer = UIGraphicsImageRenderer(size: borderSize)
        return renderer.image { context in
            // Draw border background
            color.setFill()
            if cornerRadius > 0 {
                let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: borderSize), cornerRadius: cornerRadius)
                path.fill()
            } else {
                context.fill(CGRect(origin: .zero, size: borderSize))
            }

            // Draw photo centered
            let photoRect = CGRect(x: width, y: width, width: photo.size.width, height: photo.size.height)
            if cornerRadius > 0 {
                let clipPath = UIBezierPath(roundedRect: photoRect, cornerRadius: max(0, cornerRadius - width))
                clipPath.addClip()
            }
            photo.draw(in: photoRect)
        }
    }

    /// Add a watermark text to a photo.
    func addWatermark(to photo: UIImage, text: String, opacity: CGFloat = 0.3) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: photo.size)
        return renderer.image { _ in
            photo.draw(in: CGRect(origin: .zero, size: photo.size))

            let fontSize = photo.size.width * 0.04
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(opacity)
            ]

            let textSize = (text as NSString).size(withAttributes: attributes)
            let textPoint = CGPoint(
                x: photo.size.width - textSize.width - fontSize,
                y: photo.size.height - textSize.height - fontSize
            )
            (text as NSString).draw(at: textPoint, withAttributes: attributes)
        }
    }

    // MARK: - Private Drawing

    private func drawOverlay(_ overlay: OverlayElement, in context: UIGraphicsImageRendererContext, canvasSize: CGSize) {
        let cgContext = context.cgContext

        // Calculate absolute position and size from normalized values
        let absWidth = canvasSize.width * overlay.size.width
        let absHeight = canvasSize.height * overlay.size.height
        let absX = canvasSize.width * overlay.position.x - absWidth / 2
        let absY = canvasSize.height * overlay.position.y - absHeight / 2
        let rect = CGRect(x: absX, y: absY, width: absWidth, height: absHeight)

        cgContext.saveGState()
        cgContext.setAlpha(overlay.opacity)

        // Apply rotation around center
        if overlay.rotation != 0 {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            cgContext.translateBy(x: center.x, y: center.y)
            cgContext.rotate(by: overlay.rotation * .pi / 180)
            cgContext.translateBy(x: -center.x, y: -center.y)
        }

        switch overlay.type {
        case .frame(let imageName):
            if let frameImage = UIImage(named: imageName) {
                // Frame covers entire canvas
                frameImage.draw(in: CGRect(origin: .zero, size: canvasSize))
            }

        case .logo(let imageName):
            if let logoImage = UIImage(named: imageName) {
                logoImage.draw(in: rect)
            }

        case .text(let textOverlay):
            drawText(textOverlay, in: rect)

        case .border(let borderOverlay):
            drawBorder(borderOverlay, canvasSize: canvasSize, context: cgContext)

        case .watermark(let text):
            drawWatermarkText(text, canvasSize: canvasSize)
        }

        cgContext.restoreGState()
    }

    private func drawText(_ textOverlay: TextOverlay, in rect: CGRect) {
        let font = UIFont(name: textOverlay.fontName, size: textOverlay.fontSize)
            ?? UIFont.systemFont(ofSize: textOverlay.fontSize, weight: .bold)
        let color = UIColor(hex: textOverlay.colorHex) ?? .white

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let text = textOverlay.content as NSString
        text.draw(in: rect, withAttributes: attributes)
    }

    private func drawBorder(_ border: BorderOverlay, canvasSize: CGSize, context: CGContext) {
        let color = UIColor(hex: border.colorHex) ?? .white
        color.setStroke()
        context.setLineWidth(border.width)

        let inset = border.width / 2
        let borderRect = CGRect(
            x: inset, y: inset,
            width: canvasSize.width - border.width,
            height: canvasSize.height - border.width
        )

        if border.cornerRadius > 0 {
            let path = UIBezierPath(roundedRect: borderRect, cornerRadius: border.cornerRadius)
            path.stroke()
        } else {
            context.stroke(borderRect)
        }
    }

    private func drawWatermarkText(_ text: String, canvasSize: CGSize) {
        let fontSize = canvasSize.width * 0.04
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.3)
        ]

        let textSize = (text as NSString).size(withAttributes: attributes)
        let point = CGPoint(
            x: canvasSize.width - textSize.width - fontSize,
            y: canvasSize.height - textSize.height - fontSize
        )
        (text as NSString).draw(at: point, withAttributes: attributes)
    }
}

// UIColor(hex:) is now in Common/Extensions/UIColor+Hex.swift
