import SwiftUI

/// Shows captured photo(s) for approval with accept/retake buttons.
///
/// Includes a filter picker, background picker, auto-advance timer bar, and layout support.
struct ReviewView: View {

    let photos: [CapturedPhoto]
    let onRetake: () -> Void
    let onAccept: (PhotoFilter, BackgroundOption) -> Void
    let config: SessionConfig

    @State private var timerProgress: CGFloat = 0.0
    @State private var selectedFilter: PhotoFilter = .natural
    @State private var selectedBackground: BackgroundOption = BackgroundOption.allOptions[0]
    @State private var filteredImage: UIImage?
    @State private var processedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                Text(photos.count > 1 ? "Your Photos!" : "Your Photo!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Photo display (with filter applied)
                photoDisplay
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.45)

                // Filter picker
                FilterPickerView(
                    sourceImage: photos.last?.uiImage,
                    selectedFilter: $selectedFilter
                )

                // Background picker
                BackgroundPickerView(
                    sourceImage: photos.last?.uiImage,
                    selectedBackground: $selectedBackground
                )

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
                        onAccept(selectedFilter, selectedBackground)
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
            .padding(24)
        }
        .onAppear {
            timerProgress = 0
            withAnimation(.linear(duration: config.reviewDuration)) {
                timerProgress = 1.0
            }
        }
        .onChange(of: selectedFilter) { newFilter in
            applyPreview(filter: newFilter, background: selectedBackground)
        }
        .onChange(of: selectedBackground) { newBg in
            applyPreview(filter: selectedFilter, background: newBg)
        }
    }

    // MARK: - Photo Display

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
        if let displayImage = processedImage ?? filteredImage ?? photos.last?.uiImage {
            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(12)
                .shadow(color: .white.opacity(0.1), radius: 20)
        } else if let photo = photos.last {
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

    // MARK: - Preview Generation

    private func applyPreview(filter: PhotoFilter, background: BackgroundOption) {
        guard let photo = photos.last else { return }

        let isNaturalFilter = (filter.id == "natural")
        let isOriginalBg = background.isOriginal

        // No processing needed — show original
        if isNaturalFilter && isOriginalBg {
            filteredImage = nil
            processedImage = nil
            return
        }

        let sourceImage = photo.uiImage ?? UIImage()
        let bgType = background.type

        Task.detached(priority: .userInitiated) {
            var result = sourceImage

            // Step 1: Apply filter
            if !isNaturalFilter {
                result = FilterEngine.shared.applyFilter(filter, to: result)
            }

            // Step 2: Apply background removal
            if !isOriginalBg {
                let removal = BackgroundRemoval()
                if let processed = try? await removal.removeBackground(
                    from: result,
                    replacement: bgType,
                    quality: .fast
                ) {
                    result = processed
                }
            }

            await MainActor.run {
                if isOriginalBg {
                    filteredImage = isNaturalFilter ? nil : result
                    processedImage = nil
                } else {
                    processedImage = result
                }
            }
        }
    }
}
