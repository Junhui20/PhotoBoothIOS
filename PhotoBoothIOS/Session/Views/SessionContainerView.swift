import SwiftUI

/// Root session view that manages transitions between session phases.
///
/// Shows live view in the background during active phases,
/// with phase-specific overlays on top.
struct SessionContainerView: View {

    @ObservedObject var sessionVM: SessionViewModel
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var profileManager: EventProfileManager
    @State private var showSettings = false
    @State private var showGallery = false
    @State private var activeSetting: CameraSettingsPanel.SettingType?
    @State private var isManualMode: Bool = false
    @State private var settingsTab: SettingsTab = .camera

    private enum SettingsTab { case camera, printer, events }

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
                        branding: profileManager.activeProfile.branding,
                        profileName: profileManager.activeProfile.name,
                        cameraName: cameraManager.deviceInfo.displayName,
                        batteryLevel: cameraManager.cameraSettings.batteryLevel,
                        shotCount: cameraManager.cameraSettings.availableShots,
                        onStart: { sessionVM.startSession() },
                        onSettings: { showSettings = true },
                        onGallery: { showGallery = true }
                    )
                    .transition(.opacity)

                case .ready:
                    ReadyScreen()
                        .transition(.scale)

                case .countdown(let value):
                    CountdownView(value: value)
                        .transition(.opacity)

                case .capturing:
                    if sessionVM.config.captureMode.isGIF {
                        // GIF burst capture — show recording indicator
                        GIFRecordingOverlay()
                    } else {
                        CaptureFlashView()
                    }

                case .processing:
                    ProcessingView()
                        .transition(.opacity)

                case .review:
                    if sessionVM.config.captureMode.isGIF {
                        GIFReviewView(
                            frames: sessionVM.capturedGIFFrames,
                            gifData: sessionVM.capturedGIFData,
                            isBoomerang: sessionVM.config.captureMode == .boomerangGIF,
                            onRetake: { sessionVM.retakePhoto() },
                            onAccept: { sessionVM.acceptPhotos() },
                            config: sessionVM.config
                        )
                        .transition(.move(edge: .trailing))
                    } else {
                        ReviewView(
                            photos: sessionVM.capturedPhotos,
                            onRetake: { sessionVM.retakePhoto() },
                            onAccept: { filter, background in
                                sessionVM.acceptPhotos(filter: filter, background: background)
                            },
                            config: sessionVM.config
                        )
                        .transition(.move(edge: .trailing))
                    }

                case .sharing:
                    if sessionVM.config.captureMode.isGIF {
                        ShareView(
                            photos: [],
                            selectedFilter: .natural,
                            selectedBackground: BackgroundOption.allOptions[0],
                            gifData: sessionVM.capturedGIFData,
                            onDone: { sessionVM.completeSession() }
                        )
                        .transition(.move(edge: .trailing))
                    } else {
                        ShareView(
                            photos: sessionVM.capturedPhotos,
                            selectedFilter: sessionVM.selectedFilter,
                            selectedBackground: sessionVM.selectedBackground,
                            onDone: { sessionVM.completeSession() }
                        )
                        .transition(.move(edge: .trailing))
                    }

                case .complete:
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
               !sessionVM.config.captureMode.isGIF,
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
        .sheet(isPresented: $showGallery) {
            GalleryView()
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

            // Capture mode indicator
            if sessionVM.config.captureMode.isGIF {
                Label(sessionVM.config.captureMode.displayName, systemImage: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundColor(.cyan.opacity(0.7))
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
                // Tab picker
                Picker("Settings", selection: $settingsTab) {
                    Text("Camera").tag(SettingsTab.camera)
                    Text("Printer").tag(SettingsTab.printer)
                    Text("Events").tag(SettingsTab.events)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Tab content
                switch settingsTab {
                case .camera:
                    cameraSettingsTab

                case .printer:
                    PrinterSettingsPanel()
                        .padding(.top, 16)

                case .events:
                    ProfileListView()
                        .padding(.top, 8)
                }

                Spacer()
            }
            .background(Color.black)
            .navigationTitle("Settings")
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

    /// Camera tab: settings on left, live preview on right.
    private var cameraSettingsTab: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left column — camera settings
            ScrollView {
                CameraSettingsPanel(
                    activeSetting: $activeSetting,
                    isManualMode: $isManualMode
                )
            }
            .frame(maxWidth: .infinity)

            // Right column — live preview + EV
            VStack(spacing: 12) {
                // Live camera preview
                LiveViewDisplay(
                    image: cameraManager.liveViewImage,
                    isConnected: cameraManager.connectionState.isReady
                )
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .cornerRadius(12)
                .overlay(alignment: .bottomLeading) {
                    // LIVE indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                    }
                    .padding(8)
                }

                // EV compensation slider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exposure Compensation")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text("-3")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        GeometryReader { geo in
                            let evValues = ExposureCompValue.allCases
                            let currentIndex = evValues.firstIndex(of: cameraManager.cameraSettings.exposureComp) ?? 9
                            let progress = CGFloat(currentIndex) / CGFloat(evValues.count - 1)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(red: 0.39, green: 0.4, blue: 0.95))
                                    .frame(width: geo.size.width * progress, height: 4)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 16, height: 16)
                                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                    .offset(x: geo.size.width * progress - 8)
                            }
                            .frame(height: 16)
                        }
                        .frame(height: 16)
                        Text("+3")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                .padding(16)
                .background(Color(white: 0.09))
                .cornerRadius(12)
            }
            .frame(width: 340)
            .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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

// MARK: - GIF Recording Overlay

/// Shown during GIF burst capture — pulsing indicator over live view.
private struct GIFRecordingOverlay: View {

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 20, height: 20)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.6 : 1.0)

                Text("Recording...")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }
}
