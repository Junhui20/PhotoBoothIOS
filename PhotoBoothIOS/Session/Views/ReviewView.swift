import SwiftUI
import Vision

/// Shows captured photo(s) for approval with accept/retake buttons.
///
/// Layout: timer bar at top, photo + bg pickers on left, filters on right,
/// full-width bottom action bar (Retake outlined left, Love It! gradient right).
struct ReviewView: View {

    let photos: [CapturedPhoto]
    let onRetake: () -> Void
    let onAccept: (PhotoFilter, BackgroundOption) -> Void
    let config: SessionConfig

    @State private var timerProgress: CGFloat = 0.0
    @State private var remainingSeconds: Int = 0
    @State private var selectedFilter: PhotoFilter = .natural
    @State private var selectedBackground: BackgroundOption = BackgroundOption.allOptions[0]
    @State private var filteredImage: UIImage?
    @State private var processedImage: UIImage?

    private let indigo = Color(red: 0.39, green: 0.4, blue: 0.95)

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Timer bar at top
                timerBar

                // Header
                headerRow
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)

                // Main content: photo left + filters right
                HStack(alignment: .top, spacing: 24) {
                    // Left: photo + background pickers
                    VStack(spacing: 12) {
                        photoDisplay
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()

                        BackgroundPickerView(
                            sourceImage: photos.last?.uiImage,
                            selectedBackground: $selectedBackground
                        )
                    }
                    .frame(maxWidth: .infinity)

                    // Right: filters
                    VStack(spacing: 0) {
                        FilterPickerView(
                            sourceImage: photos.last?.uiImage,
                            selectedFilter: $selectedFilter
                        )
                    }
                    .frame(width: 300)
                }
                .padding(.horizontal, 32)
                .frame(maxHeight: .infinity)

                // Bottom action bar
                actionBar
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
            }
        }
        .onAppear {
            remainingSeconds = Int(config.reviewDuration)
            timerProgress = 0
            withAnimation(.linear(duration: config.reviewDuration)) {
                timerProgress = 1.0
            }
        }
        .task {
            // Countdown for header display
            for _ in 0..<Int(config.reviewDuration) {
                try? await Task.sleep(for: .seconds(1))
                if remainingSeconds > 0 {
                    remainingSeconds -= 1
                }
            }
        }
        .onChange(of: selectedFilter) { newFilter in
            applyPreview(filter: newFilter, background: selectedBackground)
        }
        .onChange(of: selectedBackground) { newBg in
            applyPreview(filter: selectedFilter, background: newBg)
        }
    }

    // MARK: - Timer Bar

    private var timerBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [indigo, indigo.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * timerProgress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text(photos.count > 1 ? "Review Your Photos" : "Review Your Photo")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(.white)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                Text("Auto-accept in \(remainingSeconds)s")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            if config.allowRetake {
                Button(action: {
                    HapticManager.light()
                    onRetake()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16))
                        Text("Retake")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 180, height: 52)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .cornerRadius(14)
                }
            }

            Button(action: {
                HapticManager.success()
                onAccept(selectedFilter, selectedBackground)
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18))
                    Text("Love It!")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    LinearGradient(
                        colors: [indigo, Color(red: 0.31, green: 0.27, blue: 0.90)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(14)
                .shadow(color: indigo.opacity(0.25), radius: 16, y: 8)
            }
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
                .cornerRadius(16)
                .shadow(color: .white.opacity(0.05), radius: 20)
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
                .cornerRadius(16)
                .shadow(color: .white.opacity(0.05), radius: 20)
        }
    }

    // MARK: - Preview Generation

    private func applyPreview(filter: PhotoFilter, background: BackgroundOption) {
        guard let photo = photos.last else { return }

        let isNaturalFilter = (filter.id == "natural")
        let isOriginalBg = background.isOriginal

        if isNaturalFilter && isOriginalBg {
            filteredImage = nil
            processedImage = nil
            return
        }

        let sourceImage = photo.uiImage ?? UIImage()
        let bgType = background.type

        Task.detached(priority: .userInitiated) {
            let filtered = isNaturalFilter
                ? sourceImage
                : FilterEngine.shared.applyFilter(filter, to: sourceImage)

            let finalImage: UIImage
            if !isOriginalBg {
                let removal = BackgroundRemoval()
                finalImage = (try? await removal.removeBackground(
                    from: filtered,
                    replacement: bgType,
                    quality: .balanced
                )) ?? filtered
            } else {
                finalImage = filtered
            }

            await MainActor.run {
                if isOriginalBg {
                    filteredImage = isNaturalFilter ? nil : finalImage
                    processedImage = nil
                } else {
                    processedImage = finalImage
                }
            }
        }
    }
}
