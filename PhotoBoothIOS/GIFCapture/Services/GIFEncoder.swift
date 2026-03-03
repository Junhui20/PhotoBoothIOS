import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Encodes UIImage frames into animated GIF data using ImageIO.
///
/// Thread-safe — all methods are `nonisolated`. Call from `Task.detached`
/// for heavy encoding work to keep the UI responsive.
final class GIFEncoder: @unchecked Sendable {

    /// Encode frames into an animated GIF.
    ///
    /// - Parameters:
    ///   - frames: UIImage frames in order
    ///   - frameDelay: Delay between frames in seconds (e.g., 0.08)
    ///   - loopCount: 0 = infinite loop
    ///   - boomerang: If true, appends reversed frames for forward+reverse effect
    /// - Returns: GIF data, or nil if encoding fails
    nonisolated func encode(
        frames: [UIImage],
        frameDelay: TimeInterval,
        loopCount: Int = 0,
        boomerang: Bool = false
    ) -> Data? {
        guard !frames.isEmpty else { return nil }

        let allFrames: [UIImage]
        if boomerang && frames.count > 2 {
            // Forward + reverse (skip first and last of reverse to avoid stutter)
            allFrames = frames + Array(frames.dropFirst().dropLast().reversed())
        } else {
            allFrames = frames
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.gif.identifier as CFString,
            allFrames.count,
            nil
        ) else { return nil }

        // GIF-level properties: loop count
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Per-frame properties: delay time
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime as String: frameDelay,
            ]
        ]

        for frame in allFrames {
            guard let cgImage = frame.cgImage else { continue }
            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Encode with a file size limit. Downscales frames if GIF exceeds maxBytes.
    ///
    /// First tries encoding at original resolution. If the result exceeds
    /// `maxBytes`, downscales all frames to 480×320 and re-encodes.
    nonisolated func encodeWithSizeLimit(
        frames: [UIImage],
        frameDelay: TimeInterval,
        boomerang: Bool,
        maxBytes: Int = 10_000_000
    ) -> Data? {
        // Try original resolution first
        if let data = encode(frames: frames, frameDelay: frameDelay, boomerang: boomerang),
           data.count <= maxBytes {
            return data
        }

        // Downscale to 480×320 and retry
        let scaledFrames = frames.compactMap { frame -> UIImage? in
            let targetSize = scaledSize(for: frame.size, maxDimension: 480)
            return frame.preparingThumbnail(of: targetSize)
        }

        return encode(frames: scaledFrames, frameDelay: frameDelay, boomerang: boomerang)
    }

    /// Extract individual frames and delays from GIF data (for gallery playback).
    nonisolated static func extractFrames(from gifData: Data) -> [(image: UIImage, delay: TimeInterval)] {
        guard let source = CGImageSourceCreateWithData(gifData as CFData, nil) else { return [] }

        let count = CGImageSourceGetCount(source)
        var results: [(image: UIImage, delay: TimeInterval)] = []
        results.reserveCapacity(count)

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

            var delay: TimeInterval = 0.08  // default
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifDict = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                if let unclampedDelay = gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval,
                   unclampedDelay > 0 {
                    delay = unclampedDelay
                } else if let clampedDelay = gifDict[kCGImagePropertyGIFDelayTime as String] as? TimeInterval,
                          clampedDelay > 0 {
                    delay = clampedDelay
                }
            }

            results.append((image: UIImage(cgImage: cgImage), delay: delay))
        }

        return results
    }

    // MARK: - Private

    private nonisolated func scaledSize(for originalSize: CGSize, maxDimension: CGFloat) -> CGSize {
        let maxSide = max(originalSize.width, originalSize.height)
        guard maxSide > maxDimension else { return originalSize }
        let scale = maxDimension / maxSide
        return CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
    }
}
