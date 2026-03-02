import SwiftUI

/// Displays live view frames from the camera viewfinder.
struct LiveViewDisplay: View {
    let image: UIImage?
    let isConnected: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: geometry.size.width,
                            maxHeight: geometry.size.height
                        )
                } else if isConnected {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.5)
                        Text("Starting Live View…")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Connect a Canon camera via USB")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Text("Use a USB-C cable or Lightning adapter")
                            .font(.subheadline)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
            }
        }
        .clipped()
        .cornerRadius(12)
    }
}
