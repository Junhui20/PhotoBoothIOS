//
//  PhotoBoothIOSApp.swift
//  PhotoBoothIOS
//
//  Created by IM-MacMini-1 on 27/02/2026.
//

import SwiftUI

@main
struct PhotoBoothIOSApp: App {

    // Single CameraManager instance — injected into all views via .environmentObject
    @StateObject private var cameraManager = CameraManager()
    // Single PrintService instance — shared across settings, share, and print views
    @StateObject private var printService = PrintService()
    // WiFi sharing server — serves photos to guests' phones via QR code
    @StateObject private var wifiShareServer = WiFiShareServer()

    var body: some Scene {
        WindowGroup {
            SessionRootView(cameraManager: cameraManager)
                .environmentObject(cameraManager)
                .environmentObject(printService)
                .environmentObject(wifiShareServer)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .onAppear { printService.restoreDefaults() }
        }
    }
}

/// Wrapper that creates and owns SessionViewModel as @StateObject.
///
/// This avoids re-creating SessionViewModel each time the parent body evaluates.
struct SessionRootView: View {
    @StateObject private var sessionVM: SessionViewModel

    init(cameraManager: CameraManager) {
        _sessionVM = StateObject(wrappedValue: SessionViewModel(cameraManager: cameraManager))
    }

    var body: some View {
        SessionContainerView(sessionVM: sessionVM)
    }
}

