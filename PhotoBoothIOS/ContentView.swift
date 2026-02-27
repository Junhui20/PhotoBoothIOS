//
//  ContentView.swift
//  PhotoBoothIOS
//
//  Created by IM-MacMini-1 on 27/02/2026.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var cameraManager: CameraManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {

                Spacer()

                // Status indicator
                statusSection

                // Device info card (when connected)
                if cameraManager.connectionState.isReady {
                    deviceInfoCard
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    disconnectedPrompt
                }

                Spacer()
            }
            .padding(32)
            .animation(.easeInOut(duration: 0.4), value: cameraManager.connectionState)
        }
        .onAppear {
            cameraManager.startScanning()
        }
        .onDisappear {
            cameraManager.stopScanning()
        }
    }

    // MARK: - Status Indicator

    private var statusSection: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(cameraManager.connectionState.statusColor)
                .frame(width: 14, height: 14)
                .shadow(color: cameraManager.connectionState.statusColor.opacity(0.6), radius: 6)

            Text(cameraManager.connectionState.displayText)
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Device Info Card

    private var deviceInfoCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text(cameraManager.deviceInfo.displayName)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                infoRow(label: "Manufacturer", value: cameraManager.deviceInfo.manufacturer)
                infoRow(label: "Serial", value: cameraManager.deviceInfo.serialNumber)
                infoRow(label: "Firmware", value: cameraManager.deviceInfo.firmwareVersion)
                infoRow(label: "ICDevice Name", value: cameraManager.deviceInfo.name)
            }
        }
        .padding(32)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Text(value.isEmpty ? "—" : value)
                .font(.body)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Disconnected Prompt

    private var disconnectedPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("Connect a Canon camera via USB")
                .font(.title3)
                .foregroundColor(.gray)

            Text("Use a USB-C cable or Lightning adapter")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CameraManager())
}
