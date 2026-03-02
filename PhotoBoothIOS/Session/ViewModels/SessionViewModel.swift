import SwiftUI
import Combine

/// Manages the photobooth session state machine.
///
/// Flow: attract → ready → countdown → capturing → processing → review → sharing → complete → attract
@MainActor
final class SessionViewModel: ObservableObject {

    @Published var phase: SessionPhase = .attract
    @Published var countdownValue: Int = 3
    @Published var capturedPhotos: [CapturedPhoto] = []
    @Published var currentPhotoIndex: Int = 0
    @Published var retakeCount: Int = 0
    @Published var config = SessionConfig()

    let cameraManager: CameraManager
    private var countdownTimer: Timer?
    private var autoReturnTimer: Timer?

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
    }

    // MARK: - Session Control

    /// Start a new session: attract → ready → countdown.
    func startSession() {
        guard phase == .attract else { return }

        capturedPhotos = []
        currentPhotoIndex = 0
        retakeCount = 0

        HapticManager.light()
        phase = .ready

        // Brief "Get Ready!" screen, then start countdown
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard phase == .ready else { return }
            beginCountdown()
        }
    }

    /// Cancel session and return to attract.
    func cancelSession() {
        stopCountdownTimer()
        stopAutoReturnTimer()
        capturedPhotos = []
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .attract
        }
    }

    /// Retake the last photo: review → countdown.
    func retakePhoto() {
        guard phase == .review, config.allowRetake, retakeCount < config.maxRetakes else { return }

        retakeCount += 1

        // Remove the last captured photo
        if !capturedPhotos.isEmpty {
            capturedPhotos.removeLast()
            currentPhotoIndex = capturedPhotos.count
        }

        HapticManager.light()
        beginCountdown()
    }

    /// Accept captured photos: review → sharing.
    func acceptPhotos() {
        guard phase == .review else { return }

        stopAutoReturnTimer()
        HapticManager.success()

        // Auto-save to photos library if enabled
        if config.autoSaveToPhotos {
            for photo in capturedPhotos {
                if let image = photo.uiImage {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .sharing
        }

        startAutoReturnTimer()
    }

    /// Complete session: sharing → attract.
    func completeSession() {
        stopAutoReturnTimer()

        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .complete
        }

        // Brief pause, then return to attract
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeInOut(duration: 0.6)) {
                phase = .attract
            }
            capturedPhotos = []
        }
    }

    // MARK: - Countdown

    /// Start the countdown timer: 3, 2, 1 → capture.
    func beginCountdown() {
        let startValue = (currentPhotoIndex > 0) ? 2 : config.countdownSeconds
        countdownValue = startValue

        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .countdown(startValue)
        }

        stopCountdownTimer()

        if config.playCountdownBeep {
            SoundManager.shared.playCountdownBeep()
        }
        HapticManager.medium()

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.countdownTick()
            }
        }
    }

    private func countdownTick() {
        countdownValue -= 1

        if countdownValue > 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = .countdown(countdownValue)
            }
            if config.playCountdownBeep {
                SoundManager.shared.playCountdownBeep()
            }
            HapticManager.medium()
        } else {
            // Countdown reached 0 — fire shutter
            stopCountdownTimer()
            performCapture()
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Capture

    private func performCapture() {
        withAnimation(.easeIn(duration: 0.1)) {
            phase = .capturing
        }

        if config.playShutterSound {
            SoundManager.shared.playShutterClick()
        }
        HapticManager.heavy()

        Task {
            // Brief flash hold
            try? await Task.sleep(for: .milliseconds(300))

            withAnimation(.easeInOut(duration: 0.3)) {
                phase = .processing
            }

            do {
                let photo = try await cameraManager.capturePhoto()
                capturedPhotos.append(photo)
                currentPhotoIndex = capturedPhotos.count

                let requiredPhotos = config.layoutMode.photoCount
                if capturedPhotos.count < requiredPhotos {
                    // Multi-photo: show brief indicator then next countdown
                    try? await Task.sleep(for: .milliseconds(500))
                    beginCountdown()
                } else {
                    // All photos captured — show review
                    withAnimation(.easeInOut(duration: 0.4)) {
                        phase = .review
                    }
                    startAutoReturnTimer()
                }
            } catch {
                // Capture failed — show review with whatever we have, or return to attract
                if capturedPhotos.isEmpty {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        phase = .attract
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        phase = .review
                    }
                    startAutoReturnTimer()
                }
            }
        }
    }

    // MARK: - Auto Return Timer

    /// Start inactivity timer — returns to attract after timeout.
    func startAutoReturnTimer() {
        stopAutoReturnTimer()
        autoReturnTimer = Timer.scheduledTimer(
            withTimeInterval: config.autoReturnDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.completeSession()
            }
        }
    }

    /// Reset the auto-return timer (on any user interaction).
    func resetAutoReturnTimer() {
        if autoReturnTimer != nil {
            startAutoReturnTimer()
        }
    }

    private func stopAutoReturnTimer() {
        autoReturnTimer?.invalidate()
        autoReturnTimer = nil
    }
}
