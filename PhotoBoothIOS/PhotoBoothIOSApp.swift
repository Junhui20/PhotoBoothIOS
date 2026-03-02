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

    var body: some Scene {
        WindowGroup {
            SessionRootView(cameraManager: cameraManager)
                .environmentObject(cameraManager)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
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

