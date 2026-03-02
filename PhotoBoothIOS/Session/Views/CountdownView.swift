import SwiftUI

/// Large countdown number overlay (3, 2, 1) shown on top of live view.
///
/// Each number scales up with a spring animation.
/// Semi-transparent dark overlay keeps the live view visible behind.
struct CountdownView: View {

    let value: Int

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.0

    var body: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Large countdown number
            Text("\(value)")
                .font(.system(size: 200, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .white.opacity(0.3), radius: 30)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            // Reset
            scale = 0.5
            opacity = 0.0

            // Spring animation: small → large with bounce
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }

            // Fade out before next number
            withAnimation(.easeOut(duration: 0.2).delay(0.7)) {
                opacity = 0.6
            }
        }
        // Re-trigger animation when value changes
        .id(value)
    }
}
