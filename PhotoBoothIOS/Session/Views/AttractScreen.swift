import SwiftUI

/// Idle/attract screen shown when no session is active.
///
/// Shows camera connection status and animated "Tap to Start" prompt.
/// Uses branding from the active event profile for title, subtitle, and colors.
/// Gear icon in top-right opens camera settings for operator setup.
/// Gallery icon in top-left opens saved photo gallery.
struct AttractScreen: View {

    let isCameraReady: Bool
    let connectionText: String
    let branding: AttractBranding
    let profileName: String
    let onStart: () -> Void
    let onSettings: () -> Void
    let onGallery: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.4

    private var primaryColor: Color {
        Color(UIColor(hex: branding.primaryColorHex) ?? .cyan)
    }

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

                // App title (from branding)
                Text(branding.title)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 10)

                Spacer()

                if isCameraReady {
                    // Camera connected — show tap prompt
                    VStack(spacing: 16) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 44))
                            .foregroundColor(primaryColor)
                            .scaleEffect(pulseScale)
                            .shadow(color: primaryColor.opacity(glowOpacity), radius: 20)

                        Text(branding.subtitle)
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

            // Operator buttons (top corners)
            VStack {
                HStack {
                    // Gallery button (top-left) — always visible
                    Button(action: onGallery) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.5))
                            .padding(16)
                    }

                    Spacer()

                    // Settings gear button (top-right) — only when camera connected
                    if isCameraReady {
                        Button(action: onSettings) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.5))
                                .padding(16)
                        }
                    }
                }

                Spacer()

                // Active profile indicator (bottom-center, small)
                Text(profileName)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.bottom, 8)
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
