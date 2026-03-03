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
    @Published var selectedFilter: PhotoFilter = .natural
    @Published var selectedBackground: BackgroundOption = BackgroundOption.allOptions[0]
    @Published var config = SessionConfig()

    let cameraManager: CameraManager
    private var countdownTimer: Timer?
    private var autoReturnTimer: Timer?

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
    }

    nonisolated deinit {
        countdownTimer?.invalidate()
        autoReturnTimer?.invalidate()
    }

    // MARK: - Session Control

    /// Whether the camera is connected and ready for a session.
    var isCameraReady: Bool {
        cameraManager.connectionState.isReady
    }

    /// Start a new session: attract → ready → countdown.
    /// Only starts if camera is connected.
    func startSession() {
        guard phase == .attract else { return }
        guard isCameraReady else { return }

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

    /// Retake: review → attract (full restart).
    func retakePhoto() {
        guard phase == .review, config.allowRetake, retakeCount < config.maxRetakes else { return }

        retakeCount += 1
        stopAutoReturnTimer()
        capturedPhotos = []
        currentPhotoIndex = 0

        HapticManager.light()
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .attract
        }
    }

    /// Accept captured photos with selected filter and background: review → sharing.
    func acceptPhotos(
        filter: PhotoFilter = .natural,
        background: BackgroundOption = BackgroundOption.allOptions[0]
    ) {
        guard phase == .review else { return }

        stopAutoReturnTimer()
        selectedFilter = filter
        selectedBackground = background
        HapticManager.success()

        // Auto-save to photos library if enabled (apply filter + background before saving)
        if config.autoSaveToPhotos {
            let photosCopy = capturedPhotos
            let bgType = background.type
            Task {
                let pipeline = ProcessingPipeline()
                var images: [UIImage] = []
                for photo in photosCopy {
                    if let output = try? await pipeline.process(
                        photo: photo,
                        filter: filter,
                        background: background.isOriginal ? nil : bgType
                    ) {
                        images.append(output.displayImage)
                    } else if let fallback = pipeline.applyFilterOnly(to: photo, filter: filter) {
                        images.append(fallback)
                    }
                }
                PhotoLibraryHelper.saveMultipleToPhotos(images)
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
    /// Starts autofocus immediately so camera is focused when countdown reaches 0.
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

        // Start autofocus during countdown — camera focuses while timer runs
        Task {
            await cameraManager.startPreFocus()
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
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
        // Show processing immediately — no delay before capture
        withAnimation(.easeIn(duration: 0.1)) {
            phase = .processing
        }

        Task {
            do {
                let photo = try await cameraManager.capturePhoto(preFocused: true) { [weak self] in
                    // PTP response = "command received", not "shutter fired"
                    // Camera shutter fires ~150ms later — don't play iPad sound,
                    // let the camera's own shutter sound handle audio feedback.
                    guard let self else { return }
                    HapticManager.heavy()
                    // Brief flash effect
                    withAnimation(.easeIn(duration: 0.05)) {
                        self.phase = .capturing
                    }
                    // Return to processing after flash
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeOut(duration: 0.1)) {
                            self.phase = .processing
                        }
                    }
                }
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
