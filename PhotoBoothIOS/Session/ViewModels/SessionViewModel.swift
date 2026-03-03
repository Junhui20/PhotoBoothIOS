import SwiftUI
import Combine

/// Manages the photobooth session state machine.
///
/// Flow: attract → ready → countdown → capturing → processing → review → sharing → complete → attract
/// GIF flow: attract → ready → countdown → capturing (burst) → processing (encode) → review → sharing → complete → attract
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

    // GIF capture state
    @Published var capturedGIFFrames: [UIImage] = []
    @Published var capturedGIFData: Data?

    let cameraManager: CameraManager
    let galleryStore: GalleryStore
    let profileManager: EventProfileManager
    private var countdownTimer: Timer?
    private var autoReturnTimer: Timer?

    // GIF services
    private let burstService = BurstCaptureService()
    private let gifEncoder = GIFEncoder()

    init(cameraManager: CameraManager, galleryStore: GalleryStore, profileManager: EventProfileManager) {
        self.cameraManager = cameraManager
        self.galleryStore = galleryStore
        self.profileManager = profileManager
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
    /// Only starts if camera is connected. Loads config from active profile.
    func startSession() {
        guard phase == .attract else { return }
        guard isCameraReady else { return }

        // Load config from active event profile
        config = profileManager.activeProfile.config

        capturedPhotos = []
        capturedGIFFrames = []
        capturedGIFData = nil
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
        capturedGIFFrames = []
        capturedGIFData = nil
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .attract
        }
    }

    /// Retake: review → countdown restart.
    func retakePhoto() {
        guard phase == .review, config.allowRetake, retakeCount < config.maxRetakes else { return }

        retakeCount += 1
        stopAutoReturnTimer()
        capturedPhotos = []
        capturedGIFFrames = []
        capturedGIFData = nil
        currentPhotoIndex = 0

        HapticManager.light()
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .attract
        }
    }

    /// Accept captured photos with selected filter and background: review → sharing.
    ///
    /// For photo mode: processes photos and saves to camera roll + gallery.
    /// For GIF mode: saves GIF data to gallery.
    func acceptPhotos(
        filter: PhotoFilter = .natural,
        background: BackgroundOption = BackgroundOption.allOptions[0]
    ) {
        guard phase == .review else { return }

        stopAutoReturnTimer()
        selectedFilter = filter
        selectedBackground = background
        HapticManager.success()

        if config.captureMode.isGIF {
            acceptGIF()
        } else {
            acceptPhotoCapture(filter: filter, background: background)
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
            capturedGIFFrames = []
            capturedGIFData = nil
        }
    }

    // MARK: - Photo Accept (existing flow)

    private func acceptPhotoCapture(filter: PhotoFilter, background: BackgroundOption) {
        let photosCopy = capturedPhotos
        let bgType = background.type
        let saveToPhotos = config.autoSaveToPhotos
        let store = galleryStore

        Task {
            let pipeline = ProcessingPipeline()
            var displayImages: [UIImage] = []
            var shareImages: [UIImage] = []

            for photo in photosCopy {
                if let output = try? await pipeline.process(
                    photo: photo,
                    filter: filter,
                    background: background.isOriginal ? nil : bgType
                ) {
                    displayImages.append(output.displayImage)
                    shareImages.append(output.shareImage)
                } else if let fallback = pipeline.applyFilterOnly(to: photo, filter: filter) {
                    displayImages.append(fallback)
                    shareImages.append(pipeline.resizeForSharing(fallback, maxDimension: 1920))
                }
            }

            if saveToPhotos {
                PhotoLibraryHelper.saveMultipleToPhotos(displayImages)
            }

            await store.saveSession(
                photos: photosCopy,
                processedImages: displayImages,
                shareImages: shareImages,
                filter: filter,
                background: background
            )
        }
    }

    // MARK: - GIF Accept

    private func acceptGIF() {
        guard let gifData = capturedGIFData,
              let firstFrame = capturedGIFFrames.first else { return }

        let store = galleryStore
        let mode = config.captureMode
        let data = gifData

        Task {
            await store.saveGIFSession(
                gifData: data,
                thumbnailFrame: firstFrame,
                captureMode: mode
            )
        }
    }

    // MARK: - Countdown

    /// Start the countdown timer: 3, 2, 1 → capture.
    /// For photo mode: starts autofocus. For GIF mode: no pre-focus needed.
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

        // Start autofocus during countdown (photo mode only)
        if !config.captureMode.isGIF {
            Task {
                await cameraManager.startPreFocus()
            }
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
            // Countdown reached 0 — capture
            stopCountdownTimer()

            if config.captureMode.isGIF {
                performGIFCapture()
            } else {
                performCapture()
            }
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Photo Capture

    private func performCapture() {
        withAnimation(.easeIn(duration: 0.1)) {
            phase = .processing
        }

        Task {
            do {
                let photo = try await cameraManager.capturePhoto(preFocused: true) { [weak self] in
                    guard let self else { return }
                    HapticManager.heavy()
                    withAnimation(.easeIn(duration: 0.05)) {
                        self.phase = .capturing
                    }
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
                    try? await Task.sleep(for: .milliseconds(500))
                    beginCountdown()
                } else {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        phase = .review
                    }
                    startAutoReturnTimer()
                }
            } catch {
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

    // MARK: - GIF Capture

    private func performGIFCapture() {
        withAnimation(.easeIn(duration: 0.1)) {
            phase = .capturing
        }
        HapticManager.heavy()

        Task {
            // Burst-capture frames from live view
            let result = await burstService.captureFrames(
                from: cameraManager,
                frameCount: config.gifFrameCount,
                intervalMs: config.gifFrameInterval
            )

            guard !result.frames.isEmpty else {
                withAnimation(.easeInOut(duration: 0.4)) {
                    phase = .attract
                }
                return
            }

            capturedGIFFrames = result.frames

            withAnimation(.easeIn(duration: 0.2)) {
                phase = .processing
            }

            // Encode GIF on background thread
            let frames = result.frames
            let delay = result.interval
            let isBoomerang = config.captureMode == .boomerangGIF
            let encoder = gifEncoder

            let gifData = await Task.detached(priority: .userInitiated) {
                encoder.encodeWithSizeLimit(
                    frames: frames,
                    frameDelay: delay,
                    boomerang: isBoomerang
                )
            }.value

            capturedGIFData = gifData

            withAnimation(.easeInOut(duration: 0.4)) {
                phase = .review
            }
            startAutoReturnTimer()
        }
    }

    // MARK: - Auto Return Timer

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
