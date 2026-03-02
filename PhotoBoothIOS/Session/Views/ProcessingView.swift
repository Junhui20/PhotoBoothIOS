import SwiftUI

/// "Processing..." spinner shown while downloading the captured photo.
struct ProcessingView: View {

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(2.0)

                Text("Processing…")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
    }
}
