import SwiftUI

/// Review screen for GIF captures — plays the animated GIF in a loop.
///
/// Uses UIViewRepresentable wrapping UIImageView for smooth animated playback.
/// No filter/background pickers (GIF frames are live view resolution).
struct GIFReviewView: View {

    let frames: [UIImage]
    let gifData: Data?
    let isBoomerang: Bool
    let onRetake: () -> Void
    let onAccept: () -> Void
    let config: SessionConfig

    @State private var timerProgress: CGFloat = 0.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Animated GIF playback
                if !frames.isEmpty {
                    AnimatedGIFView(
                        frames: animationFrames,
                        frameDuration: Double(config.gifFrameInterval) / 1000.0
                    )
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.5), radius: 20)
                    .padding(.horizontal, 20)
                }

                // Info bar
                HStack(spacing: 16) {
                    Label(
                        "\(frames.count) frames",
                        systemImage: "photo.stack"
                    )

                    if let data = gifData {
                        Label(
                            formatBytes(data.count),
                            systemImage: "doc"
                        )
                    }

                    Label(
                        isBoomerang ? "Boomerang" : "Burst",
                        systemImage: isBoomerang ? "arrow.2.squarepath" : "photo.stack"
                    )
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))

                Spacer()

                // Action buttons
                HStack(spacing: 16) {
                    if config.allowRetake {
                        Button(action: onRetake) {
                            Label("Retake", systemImage: "arrow.counterclockwise")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(16)
                        }
                    }

                    Button(action: onAccept) {
                        Label("Love it!", systemImage: "heart.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green)
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Auto-advance timer bar
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: geo.size.width * timerProgress, height: 3)
                }
                .frame(height: 3)
            }
        }
        .onAppear {
            startAutoAdvanceTimer()
        }
    }

    /// Frames for animation — boomerang appends reversed frames.
    private var animationFrames: [UIImage] {
        if isBoomerang && frames.count > 2 {
            return frames + Array(frames.dropFirst().dropLast().reversed())
        }
        return frames
    }

    private func startAutoAdvanceTimer() {
        timerProgress = 0
        withAnimation(.linear(duration: config.reviewDuration)) {
            timerProgress = 1.0
        }

        Task {
            try? await Task.sleep(for: .seconds(config.reviewDuration))
            onAccept()
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Animated GIF UIViewRepresentable

/// Wraps UIImageView for smooth animated GIF playback.
///
/// `UIImageView.animatedImage(with:duration:)` provides hardware-accelerated
/// frame cycling — much smoother than Timer-based SwiftUI Image switching.
struct AnimatedGIFView: UIViewRepresentable {

    let frames: [UIImage]
    let frameDuration: TimeInterval

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        configureAnimation(imageView)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        configureAnimation(uiView)
    }

    private func configureAnimation(_ imageView: UIImageView) {
        guard !frames.isEmpty else { return }

        let totalDuration = frameDuration * Double(frames.count)
        imageView.animationImages = frames
        imageView.animationDuration = totalDuration
        imageView.animationRepeatCount = 0  // Infinite loop
        imageView.startAnimating()
    }
}
