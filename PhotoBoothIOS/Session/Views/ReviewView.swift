import SwiftUI

/// Shows captured photo(s) for approval with accept/retake buttons.
///
/// Includes an auto-advance timer bar that fills over the review duration.
/// For multi-photo sessions, shows all photos in their layout arrangement.
struct ReviewView: View {

    let photos: [CapturedPhoto]
    let onRetake: () -> Void
    let onAccept: () -> Void
    let config: SessionConfig

    @State private var timerProgress: CGFloat = 0.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                Text(photos.count > 1 ? "Your Photos!" : "Your Photo!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Photo display
                photoDisplay
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.55)

                // Action buttons
                HStack(spacing: 24) {
                    if config.allowRetake {
                        Button(action: {
                            HapticManager.light()
                            onRetake()
                        }) {
                            Label("Retake", systemImage: "arrow.counterclockwise")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 36)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(16)
                        }
                    }

                    Button(action: {
                        HapticManager.success()
                        onAccept()
                    }) {
                        Label("Love it!", systemImage: "heart.fill")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 36)
                            .padding(.vertical, 16)
                            .background(Color.pink)
                            .cornerRadius(16)
                    }
                }

                // Auto-advance timer bar
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.cyan)
                                .frame(width: geo.size.width * timerProgress, height: 4)
                        }
                }
                .frame(height: 4)
                .padding(.horizontal, 40)
            }
            .padding(32)
        }
        .onAppear {
            timerProgress = 0
            withAnimation(.linear(duration: config.reviewDuration)) {
                timerProgress = 1.0
            }
        }
    }

    @ViewBuilder
    private var photoDisplay: some View {
        switch config.layoutMode {
        case .single:
            singlePhotoView
        case .duo:
            HStack(spacing: 8) {
                ForEach(photos) { photo in
                    photoImage(photo)
                }
            }
        case .strip:
            VStack(spacing: 8) {
                ForEach(photos) { photo in
                    photoImage(photo)
                }
            }
        case .grid4:
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(photos) { photo in
                    photoImage(photo)
                }
            }
        }
    }

    @ViewBuilder
    private var singlePhotoView: some View {
        if let photo = photos.last {
            photoImage(photo)
        }
    }

    @ViewBuilder
    private func photoImage(_ photo: CapturedPhoto) -> some View {
        if let image = photo.uiImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(12)
                .shadow(color: .white.opacity(0.1), radius: 20)
        }
    }
}
