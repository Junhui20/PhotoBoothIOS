import SwiftUI

/// Idle/attract screen shown when no session is active.
///
/// Full-screen dark background with animated "Tap to Start" prompt.
/// Tapping anywhere starts a new session.
struct AttractScreen: View {

    let onStart: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.4

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [Color.black, Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Camera icon
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.3))

                // App title
                Text("PhotoBooth Pro")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                // Animated "Tap to Start" prompt
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

                Spacer()
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onStart()
        }
    }
}
