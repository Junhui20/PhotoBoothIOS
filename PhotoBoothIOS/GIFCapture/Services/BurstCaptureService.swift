import UIKit

/// Result of a burst capture — ordered frames from the live view stream.
struct BurstCaptureResult: Sendable {
    let frames: [UIImage]
    let interval: TimeInterval   // Seconds between frames
}

/// Captures a burst of frames from the camera's live view stream.
///
/// Instead of firing the shutter, this samples `CameraManager.liveViewImage`
/// at regular intervals. Each frame is ~960×640 (live view JPEG resolution).
/// Silent (no shutter sound), fast (no PTP download per frame), smooth.
///
/// Memory: 12 frames × 960×640 RGBA ≈ 30MB — acceptable for iPad.
final class BurstCaptureService {

    /// Capture frames from the live view at specified intervals.
    ///
    /// Live view must be active (streaming) before calling this method.
    /// The live view loop continues running throughout the burst — we simply
    /// snapshot the latest frame at each interval.
    ///
    /// - Parameters:
    ///   - cameraManager: The camera providing live view frames
    ///   - frameCount: Number of frames to capture (8-24, default 12)
    ///   - intervalMs: Milliseconds between frames (40-200, default 80)
    /// - Returns: BurstCaptureResult with captured frames
    func captureFrames(
        from cameraManager: CameraManager,
        frameCount: Int,
        intervalMs: Int
    ) async -> BurstCaptureResult {
        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            // Snapshot the current live view frame (MainActor property)
            let frame = await MainActor.run { cameraManager.liveViewImage }
            if let frame {
                frames.append(frame)
            }

            // Wait for next frame interval (skip on last frame)
            if i < frameCount - 1 {
                try? await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
            }
        }

        return BurstCaptureResult(
            frames: frames,
            interval: Double(intervalMs) / 1000.0
        )
    }
}
