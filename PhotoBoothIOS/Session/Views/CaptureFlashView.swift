import SwiftUI

/// Brief white flash overlay when shutter fires.
///
/// Full screen white that fades in quickly and fades out slowly,
/// simulating a camera flash effect.
struct CaptureFlashView: View {

    @State private var opacity: Double = 0.0

    var body: some View {
        Color.white
            .ignoresSafeArea()
            .opacity(opacity)
            .onAppear {
                // Quick fade in
                withAnimation(.easeIn(duration: 0.1)) {
                    opacity = 1.0
                }
                // Hold briefly, then fade out
                withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                    opacity = 0.0
                }
            }
            .allowsHitTesting(false)
    }
}
