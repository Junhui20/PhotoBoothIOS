import SwiftUI

/// Brief "Get Ready!" screen shown between attract and countdown.
///
/// Displays for ~1.5 seconds to give the user time to prepare.
struct ReadyScreen: View {

    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "face.smiling.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)

                Text("Get Ready!")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
        }
    }
}
