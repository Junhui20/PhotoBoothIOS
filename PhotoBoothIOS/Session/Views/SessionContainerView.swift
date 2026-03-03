import SwiftUI

/// Root session view that manages transitions between session phases.
///
/// Shows live view in the background during active phases,
/// with phase-specific overlays on top.
struct SessionContainerView: View {

    @ObservedObject var sessionVM: SessionViewModel
    @EnvironmentObject var cameraManager: CameraManager
    @State private var showSettings = false
    @State private var activeSetting: CameraSettingsPanel.SettingType?
    @State private var isManualMode: Bool = false

    var body: some View {
        ZStack {
            // Live view background — shown during ALL phases when camera is connected
            if cameraManager.connectionState.isReady {
                LiveViewDisplay(
                    image: cameraManager.liveViewImage,
                    isConnected: true
                )
                .ignoresSafeArea()
            }

            // Phase-specific overlays
            Group {
                switch sessionVM.phase {
                case .attract:
                    AttractScreen(
                        isCameraReady: cameraManager.connectionState.isReady,
                        connectionText: cameraManager.connectionState.displayText,
                        onStart: { sessionVM.startSession() },
                        onSettings: { showSettings = true }
                    )
                    .transition(.opacity)

                case .ready:
                    ReadyScreen()
                        .transition(.scale)

                case .countdown(let value):
                    CountdownView(value: value)
                        .transition(.opacity)

                case .capturing:
                    CaptureFlashView()
                        .transition(.opacity)

                case .processing:
                    ProcessingView()
                        .transition(.opacity)

                case .review:
                    ReviewView(
                        photos: sessionVM.capturedPhotos,
                        onRetake: { sessionVM.retakePhoto() },
                        onAccept: { filter, background in
                            sessionVM.acceptPhotos(filter: filter, background: background)
                        },
                        config: sessionVM.config
                    )
                    .transition(.move(edge: .trailing))

                case .sharing:
                    ShareView(
                        photos: sessionVM.capturedPhotos,
                        selectedFilter: sessionVM.selectedFilter,
                        selectedBackground: sessionVM.selectedBackground,
                        onDone: { sessionVM.completeSession() }
                    )
                    .transition(.move(edge: .trailing))

                case .complete:
                    // Brief moment before returning to attract
                    Color.black.ignoresSafeArea()
                        .transition(.opacity)
                }
            }

            // Status bar overlay (visible during active session phases)
            if sessionVM.phase != .attract {
                VStack {
                    sessionStatusBar
                    Spacer()
                }
            }

            // Multi-photo progress indicator
            if case .countdown = sessionVM.phase,
               sessionVM.config.layoutMode != .single {
                VStack {
                    Spacer()
                    photoProgressIndicator
                        .padding(.bottom, 40)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: sessionVM.phase)
        .onAppear {
            cameraManager.startScanning()
        }
        .onDisappear {
            cameraManager.stopScanning()
        }
        // Detect photos from camera's physical shutter button during attract/active
        .onChange(of: cameraManager.lastCapturedPhoto?.id) { _ in
            handleExternalCapture()
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    // MARK: - Status Bar

    private var sessionStatusBar: some View {
        HStack {
            // Connection indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(cameraManager.connectionState.statusColor)
                    .frame(width: 10, height: 10)
                Text(cameraManager.deviceInfo.displayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // Cancel button (not on attract/complete)
            if sessionVM.phase != .complete {
                Button(action: { sessionVM.cancelSession() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Multi-Photo Progress

    private var photoProgressIndicator: some View {
        let total = sessionVM.config.layoutMode.photoCount
        let current = sessionVM.currentPhotoIndex + 1

        return HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < sessionVM.currentPhotoIndex ? Color.green : (index == sessionVM.currentPhotoIndex ? Color.cyan : Color.white.opacity(0.3)))
                    .frame(width: 12, height: 12)
            }
            Text("Photo \(current) of \(total)")
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.6))
        .cornerRadius(20)
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Live view preview at top
                LiveViewDisplay(
                    image: cameraManager.liveViewImage,
                    isConnected: cameraManager.connectionState.isReady
                )
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Camera settings panel
                CameraSettingsPanel(
                    activeSetting: $activeSetting,
                    isManualMode: $isManualMode
                )
                .padding(.top, 8)

                Spacer()
            }
            .background(Color.black)
            .navigationTitle("Camera Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - External Capture Handling

    /// When the camera's physical shutter button is pressed during a session,
    /// treat it as a capture event.
    private func handleExternalCapture() {
        if sessionVM.phase == .attract {
            // Camera shutter pressed on attract → start session immediately
            // The photo is already in cameraManager.lastCapturedPhoto
        }
        // During active session, SessionViewModel handles capture via cameraManager.capturePhoto()
    }
}
