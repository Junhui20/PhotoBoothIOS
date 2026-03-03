import SwiftUI

/// Idle/attract screen shown when no session is active.
///
/// Shows camera connection status and animated "Tap to Start" prompt.
/// Gear icon in corner opens camera settings for operator setup.
struct AttractScreen: View {

    let isCameraReady: Bool
    let connectionText: String
    let onStart: () -> Void
    let onSettings: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.4

    var body: some View {
        ZStack {
            if isCameraReady {
                // Semi-transparent overlay over live preview
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
            } else {
                // No camera — solid dark background
                LinearGradient(
                    colors: [Color.black, Color(white: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 40) {
                Spacer()

                // App title
                Text("PhotoBooth Pro")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 10)

                Spacer()

                if isCameraReady {
                    // Camera connected — show "Tap to Start"
                    VStack(spacing: 16) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.cyan)
                            .scaleEffect(pulseScale)
                            .shadow(color: .cyan.opacity(glowOpacity), radius: 20)

                        Text("Tap to Start")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .scaleEffect(pulseScale)
                    }
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true)
                        ) {
                            pulseScale = 1.08
                            glowOpacity = 0.8
                        }
                    }
                } else {
                    // Camera not connected — show connection status
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.yellow)
                            .scaleEffect(1.5)

                        Text(connectionText)
                            .font(.title3)
                            .foregroundColor(.yellow)

                        Text("Connect a Canon camera via USB to begin")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer()
                Spacer()
            }

            // Settings gear button (top-right corner) — only when camera connected
            if isCameraReady {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onSettings) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.5))
                                .padding(16)
                        }
                    }
                    Spacer()
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isCameraReady {
                onStart()
            }
        }
    }
}
