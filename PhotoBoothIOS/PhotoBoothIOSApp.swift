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
    // Gallery storage — persists sessions to disk for browsing and re-sharing
    @StateObject private var galleryStore = GalleryStore()
    // Event profile management — branding and session config per event
    @StateObject private var profileManager = EventProfileManager()

    var body: some Scene {
        WindowGroup {
            SessionRootView(
                cameraManager: cameraManager,
                galleryStore: galleryStore,
                profileManager: profileManager
            )
            .environmentObject(cameraManager)
            .environmentObject(printService)
            .environmentObject(wifiShareServer)
            .environmentObject(galleryStore)
            .environmentObject(profileManager)
            .preferredColorScheme(.dark)
            .statusBarHidden(true)
            .onAppear {
                printService.restoreDefaults()
                galleryStore.loadSessions()
                profileManager.loadProfiles()
            }
        }
    }
}

/// Wrapper that creates and owns SessionViewModel as @StateObject.
///
/// This avoids re-creating SessionViewModel each time the parent body evaluates.
struct SessionRootView: View {
    @StateObject private var sessionVM: SessionViewModel

    init(cameraManager: CameraManager, galleryStore: GalleryStore, profileManager: EventProfileManager) {
        _sessionVM = StateObject(wrappedValue: SessionViewModel(
            cameraManager: cameraManager,
            galleryStore: galleryStore,
            profileManager: profileManager
        ))
    }

    var body: some View {
        SessionContainerView(sessionVM: sessionVM)
    }
}
