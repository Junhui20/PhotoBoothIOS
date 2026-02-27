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
            ContentView()
                .environmentObject(cameraManager)
                .preferredColorScheme(.dark)
        }
    }
}
