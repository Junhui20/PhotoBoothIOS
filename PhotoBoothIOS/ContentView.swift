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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                liveViewArea
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                controlBar
                    .padding(.vertical, 20)
            }

            // Capture flash overlay
            if captureFlash {
                Color.white.ignoresSafeArea()
                    .transition(.opacity)
            }

            // Captured photo overlay
            if showCapturedPhoto, let photo = cameraManager.lastCapturedPhoto {
                capturedPhotoOverlay(photo: photo)
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
                Text(cameraManager.deviceInfo.displayName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
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
        Task {
            do {
                withAnimation(.easeIn(duration: 0.1)) { captureFlash = true }
                _ = try await cameraManager.capturePhoto()
                withAnimation(.easeOut(duration: 0.3)) { captureFlash = false }
                showCapturedPhoto = true
            } catch {
                captureFlash = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Captured Photo Overlay

    private func capturedPhotoOverlay(photo: CapturedPhoto) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
                .onTapGesture { showCapturedPhoto = false }

            VStack(spacing: 24) {
                Text("Photo Captured!")
                    .font(.title).fontWeight(.bold)
                    .foregroundColor(.white)

                if let image = photo.uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 500)
                        .cornerRadius(12)
                        .shadow(radius: 20)
                }

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
                        if let image = photo.uiImage {
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
            .padding(40)
        }
        .transition(.opacity)
    }
}

#Preview {
    ContentView()
        .environmentObject(CameraManager())
}
