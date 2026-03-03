import UIKit
import os

// MARK: - Print Layout Renderer

/// Renders photos into print layout templates at arbitrary DPI.
///
/// Uses UIGraphicsImageRenderer for compositing (same pattern as OverlayEngine).
/// Thread-safe — all methods are nonisolated for background rendering.
final class PrintLayoutRenderer: @unchecked Sendable {

    nonisolated static let shared = PrintLayoutRenderer()

    private nonisolated let logger = Logger(
        subsystem: "com.photobooth.printing", category: "Renderer"
    )

    nonisolated private init() {}

    // MARK: - Public API

    /// Render a complete print layout at full print quality.
    nonisolated func render(
        layout: PrintLayout,
        photos: [UIImage],
        textValues: [String: String] = [:],
        dpi: Int = 300
    ) -> Result<UIImage, PrintError> {
        guard photos.count >= layout.requiredPhotoCount else {
            return .failure(.insufficientPhotos(
                required: layout.requiredPhotoCount, provided: photos.count))
        }

        let canvasSize = layout.canvasPixelSize(dpi: dpi)
        let safeArea = layout.safeAreaRect(dpi: dpi)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0      // 1:1 pixel mapping for print
        format.opaque = true    // No transparency — saves memory

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        let image = renderer.image { context in
            drawBackground(layout.background, canvasSize: canvasSize, ctx: context)

            for slot in layout.photoSlots {
                let photoIndex = slot.id % layout.requiredPhotoCount
                guard photoIndex < photos.count else { continue }
                drawPhoto(photos[photoIndex], in: slot, safeArea: safeArea, ctx: context.cgContext)
            }

            for zone in layout.textZones {
                let text = resolveText(zone, values: textValues)
                drawText(text, in: zone, safeArea: safeArea, canvasHeight: canvasSize.height)
            }

            if layout.id == "duplicate_strip" {
                drawCutLine(canvasSize: canvasSize, ctx: context.cgContext)
            }
        }

        logger.info("Rendered \(layout.name) at \(dpi) DPI: \(Int(canvasSize.width))×\(Int(canvasSize.height))")
        return .success(image)
    }

    /// Render a preview at reduced DPI to fit a given screen width.
    nonisolated func renderPreview(
        layout: PrintLayout,
        photos: [UIImage],
        textValues: [String: String] = [:],
        maxWidth: CGFloat = 800
    ) -> Result<UIImage, PrintError> {
        let effectiveWidth: CGFloat
        switch layout.orientation {
        case .portrait:  effectiveWidth = layout.paperSize.widthInches
        case .landscape: effectiveWidth = layout.paperSize.heightInches
        }

        let totalWidth = effectiveWidth + layout.bleedInches * 2
        let previewDPI = max(72, Int(maxWidth / totalWidth))

        return render(layout: layout, photos: photos, textValues: textValues, dpi: previewDPI)
    }

    // MARK: - Background

    private nonisolated func drawBackground(
        _ background: PrintBackground,
        canvasSize: CGSize,
        ctx: UIGraphicsImageRendererContext
    ) {
        let fullRect = CGRect(origin: .zero, size: canvasSize)

        switch background {
        case .white:
            UIColor.white.setFill()
            ctx.fill(fullRect)

        case .solidColor(let hex):
            let color = UIColor(hex: hex) ?? .white
            color.setFill()
            ctx.fill(fullRect)

        case .gradient(let topHex, let bottomHex):
            let topColor = UIColor(hex: topHex) ?? .white
            let bottomColor = UIColor(hex: bottomHex) ?? .white
            let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: canvasSize.height),
                    options: []
                )
            }
        }
    }

    // MARK: - Photo Drawing

    private nonisolated func drawPhoto(
        _ photo: UIImage,
        in slot: PhotoSlot,
        safeArea: CGRect,
        ctx: CGContext
    ) {
        // Convert normalized rect to absolute pixels within safe area
        let absoluteRect = CGRect(
            x: safeArea.origin.x + slot.rect.origin.x * safeArea.width,
            y: safeArea.origin.y + slot.rect.origin.y * safeArea.height,
            width: slot.rect.width * safeArea.width,
            height: slot.rect.height * safeArea.height
        )

        ctx.saveGState()

        // Corner radius clipping
        if slot.cornerRadius > 0 {
            let radius = slot.cornerRadius * min(absoluteRect.width, absoluteRect.height)
            let path = UIBezierPath(roundedRect: absoluteRect, cornerRadius: radius)
            path.addClip()
        } else {
            // Still clip to the rect boundary
            ctx.addRect(absoluteRect)
            ctx.clip()
        }

        // Rotation
        if slot.rotation != 0 {
            let center = CGPoint(x: absoluteRect.midX, y: absoluteRect.midY)
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: slot.rotation * .pi / 180)
            ctx.translateBy(x: -center.x, y: -center.y)
        }

        // Draw photo (aspect-fill or aspect-fit)
        let drawRect = slot.aspectFill
            ? aspectFillRect(for: photo.size, in: absoluteRect)
            : aspectFitRect(for: photo.size, in: absoluteRect)
        photo.draw(in: drawRect)

        ctx.restoreGState()

        // Border (drawn after restoring state so it's not clipped)
        if slot.borderWidth > 0 {
            ctx.saveGState()
            let borderColor = UIColor(hex: slot.borderColorHex) ?? .white
            borderColor.setStroke()
            ctx.setLineWidth(slot.borderWidth)
            if slot.cornerRadius > 0 {
                let radius = slot.cornerRadius * min(absoluteRect.width, absoluteRect.height)
                let borderPath = UIBezierPath(roundedRect: absoluteRect, cornerRadius: radius)
                borderPath.stroke()
            } else {
                ctx.stroke(absoluteRect)
            }
            ctx.restoreGState()
        }
    }

    // MARK: - Text Drawing

    private nonisolated func resolveText(_ zone: TextZone, values: [String: String]) -> String {
        // Check for direct value match
        if let value = values[zone.id], !value.isEmpty {
            return value
        }
        // For duplicate strip right-side text, try the base id
        let baseId = zone.id.replacingOccurrences(of: "_right", with: "")
        if let value = values[baseId], !value.isEmpty {
            return value
        }
        return zone.defaultText
    }

    private nonisolated func drawText(
        _ text: String,
        in zone: TextZone,
        safeArea: CGRect,
        canvasHeight: CGFloat
    ) {
        guard !text.isEmpty else { return }

        let absoluteRect = CGRect(
            x: safeArea.origin.x + zone.rect.origin.x * safeArea.width,
            y: safeArea.origin.y + zone.rect.origin.y * safeArea.height,
            width: zone.rect.width * safeArea.width,
            height: zone.rect.height * safeArea.height
        )

        let fontSize = zone.fontSizeRatio * canvasHeight
        let font = UIFont(name: zone.fontName, size: fontSize)
            ?? UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let color = UIColor(hex: zone.colorHex) ?? .black

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = zone.alignment
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]

        (text as NSString).draw(
            with: absoluteRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes,
            context: nil
        )
    }

    // MARK: - Cut Line

    private nonisolated func drawCutLine(canvasSize: CGSize, ctx: CGContext) {
        let centerX = canvasSize.width / 2
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.lightGray.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [8, 5])
        ctx.move(to: CGPoint(x: centerX, y: 0))
        ctx.addLine(to: CGPoint(x: centerX, y: canvasSize.height))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Geometry Helpers

    /// Calculate rect that fills the target while maintaining aspect ratio (may crop).
    private nonisolated func aspectFillRect(for imageSize: CGSize, in targetRect: CGRect) -> CGRect {
        let widthRatio = targetRect.width / imageSize.width
        let heightRatio = targetRect.height / imageSize.height
        let scale = max(widthRatio, heightRatio)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale

        return CGRect(
            x: targetRect.midX - scaledWidth / 2,
            y: targetRect.midY - scaledHeight / 2,
            width: scaledWidth,
            height: scaledHeight
        )
    }

    /// Calculate rect that fits inside the target while maintaining aspect ratio (may letterbox).
    private nonisolated func aspectFitRect(for imageSize: CGSize, in targetRect: CGRect) -> CGRect {
        let widthRatio = targetRect.width / imageSize.width
        let heightRatio = targetRect.height / imageSize.height
        let scale = min(widthRatio, heightRatio)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale

        return CGRect(
            x: targetRect.midX - scaledWidth / 2,
            y: targetRect.midY - scaledHeight / 2,
            width: scaledWidth,
            height: scaledHeight
        )
    }
}
