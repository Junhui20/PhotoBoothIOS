//
//  ContentView.swift
//  PhotoBoothIOS
//
//  Created by IM-MacMini-1 on 27/02/2026.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var cameraManager: CameraManager
    @State private var showCapturedPhoto = false
    @State private var captureFlash = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var activeSetting: CameraSettingsPanel.SettingType?
    @State private var isManualMode: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                liveViewArea
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Camera settings panel (when connected)
                if cameraManager.connectionState.isReady {
                    CameraSettingsPanel(
                        activeSetting: $activeSetting,
                        isManualMode: $isManualMode
                    )
                    .padding(.top, 8)
                }

                controlBar
                    .padding(.vertical, 20)
            }

            // Capture flash overlay
            if captureFlash {
                Color.white.ignoresSafeArea()
                    .transition(.opacity)
            }

            // Captured photo overlay (instant preview → full-res)
            if showCapturedPhoto {
                capturedPhotoOverlay
            }
        }
        .onAppear { cameraManager.startScanning() }
        .onDisappear { cameraManager.stopScanning() }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .animation(.easeInOut(duration: 0.4), value: cameraManager.connectionState)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(cameraManager.connectionState.statusColor)
                    .frame(width: 12, height: 12)
                    .shadow(
                        color: cameraManager.connectionState.statusColor.opacity(0.6),
                        radius: 6
                    )
                Text(cameraManager.connectionState.displayText)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }

            Spacer()

            if cameraManager.connectionState.isReady {
                HStack(spacing: 12) {
                    // Battery level (Canon EOS reports 0-3 scale, not percentage)
                    if cameraManager.cameraSettings.batteryLevel >= 0 {
                        HStack(spacing: 3) {
                            Image(systemName: batteryIconName)
                            Text(batteryDisplayText)
                                .font(.caption)
                        }
                        .foregroundColor(batteryColor)
                    }

                    // Available shots
                    if cameraManager.cameraSettings.availableShots > 0 {
                        Text("\(cameraManager.cameraSettings.availableShots)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text(cameraManager.deviceInfo.displayName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
    }

    // MARK: - Live View

    private var liveViewArea: some View {
        LiveViewDisplay(
            image: cameraManager.liveViewImage,
            isConnected: cameraManager.connectionState.isReady
        )
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 40) {
            // Gallery thumbnail (last captured photo)
            lastPhotoThumbnail

            // Capture button
            captureButton

            // Placeholder for future controls (settings, switch camera, etc.)
            Color.clear.frame(width: 60, height: 60)
        }
        .padding(.horizontal, 40)
    }

    private var lastPhotoThumbnail: some View {
        Group {
            if let photo = cameraManager.lastCapturedPhoto,
               let image = photo.uiImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { showCapturedPhoto = true }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
        }
    }

    private var captureButton: some View {
        Button(action: { triggerCapture() }) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(cameraManager.isCapturing ? Color.gray : Color.white)
                    .frame(width: 68, height: 68)
            }
        }
        .disabled(cameraManager.isCapturing || !cameraManager.connectionState.isReady)
        .scaleEffect(cameraManager.isCapturing ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: cameraManager.isCapturing)
    }

    // MARK: - Capture Action

    private func triggerCapture() {
        activeSetting = nil // Dismiss settings picker
        Task {
            do {
                withAnimation(.easeIn(duration: 0.1)) { captureFlash = true }

                // Show preview overlay immediately (uses last live view frame)
                showCapturedPhoto = true

                _ = try await cameraManager.capturePhoto()
                withAnimation(.easeOut(duration: 0.3)) { captureFlash = false }
                // Overlay auto-updates: preview → full-res when lastCapturedPhoto arrives
            } catch {
                captureFlash = false
                showCapturedPhoto = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Battery Helpers
    // Canon EOS cameras report battery as 0-3 levels (not 0-100 percentage):
    //   0 = critical, 1 = low, 2 = half, 3 = full

    private var batteryIconName: String {
        let level = cameraManager.cameraSettings.batteryLevel
        switch level {
        case 0:  return "battery.0percent"
        case 1:  return "battery.25percent"
        case 2:  return "battery.50percent"
        case 3:  return "battery.100percent"
        default: return "battery.100percent"
        }
    }

    private var batteryDisplayText: String {
        let level = cameraManager.cameraSettings.batteryLevel
        switch level {
        case 0:  return "Low!"
        case 1:  return "Low"
        case 2:  return "OK"
        case 3:  return "Full"
        default: return ""
        }
    }

    private var batteryColor: Color {
        let level = cameraManager.cameraSettings.batteryLevel
        switch level {
        case 0:  return .red
        case 1:  return .orange
        default: return .green
        }
    }

    // MARK: - Captured Photo Overlay

    /// Shows instant preview immediately, auto-upgrades to full-res when download completes.
    private var capturedPhotoOverlay: some View {
        let fullResImage = cameraManager.lastCapturedPhoto?.uiImage
        let previewImage = cameraManager.capturePreviewImage
        let displayImage = fullResImage ?? previewImage
        let isDownloading = (fullResImage == nil && cameraManager.isCapturing)

        return ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
                .onTapGesture {
                    if !cameraManager.isCapturing { showCapturedPhoto = false }
                }

            VStack(spacing: 24) {
                if isDownloading {
                    Text("Downloading…")
                        .font(.title).fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Text("Photo Captured!")
                        .font(.title).fontWeight(.bold)
                        .foregroundColor(.white)
                }

                if let image = displayImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 500)
                        .cornerRadius(12)
                        .shadow(radius: 20)
                        .overlay(
                            // Loading indicator on preview image
                            Group {
                                if isDownloading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.5)
                                }
                            }
                        )
                }

                if !cameraManager.isCapturing {
                    HStack(spacing: 20) {
                        Button(action: { showCapturedPhoto = false }) {
                            Label("Retake", systemImage: "arrow.counterclockwise")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(Color.gray.opacity(0.5))
                                .cornerRadius(12)
                        }

                        Button(action: {
                            if let photo = cameraManager.lastCapturedPhoto,
                               let image = photo.uiImage {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            }
                            showCapturedPhoto = false
                        }) {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                }
            }
            .padding(40)
        }
        .transition(.opacity)
    }
}

#Preview {
    ContentView()
        .environmentObject(CameraManager())
}
