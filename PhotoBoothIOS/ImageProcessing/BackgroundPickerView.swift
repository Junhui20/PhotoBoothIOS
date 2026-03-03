import SwiftUI
import Vision

/// Predefined background option for the picker.
struct BackgroundOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let type: BackgroundType

    nonisolated static func == (lhs: BackgroundOption, rhs: BackgroundOption) -> Bool {
        lhs.id == rhs.id
    }
}

nonisolated extension BackgroundOption {

    /// Check if this is the "original" (no change) option.
    var isOriginal: Bool { id == "original" }

    static let allOptions: [BackgroundOption] = [
        BackgroundOption(id: "original", name: "Original", type: .original),
        BackgroundOption(id: "blur", name: "Blur", type: .blurred(radius: 20)),
        BackgroundOption(id: "white", name: "White", type: .solidColor(.white)),
        BackgroundOption(id: "black", name: "Black", type: .solidColor(.black)),
        BackgroundOption(id: "blue", name: "Blue", type: .solidColor(UIColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1))),
        BackgroundOption(id: "gradient_warm", name: "Warm", type: .gradient(
            UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1),
            UIColor(red: 0.8, green: 0.1, blue: 0.3, alpha: 1)
        )),
        BackgroundOption(id: "gradient_cool", name: "Cool", type: .gradient(
            UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1),
            UIColor(red: 0.1, green: 0.1, blue: 0.4, alpha: 1)
        )),
    ]
}

/// Horizontal scrollable background picker showing preview thumbnails.
///
/// Each thumbnail shows the current photo with a different background applied.
/// Uses Vision person segmentation for real-time previews.
struct BackgroundPickerView: View {

    let sourceImage: UIImage?
    @Binding var selectedBackground: BackgroundOption

    @State private var thumbnails: [String: UIImage] = [:]
    @State private var isGenerating = false
    @State private var segmentationAvailable = true

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.rectangle")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                Text("Background")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }

            if segmentationAvailable {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(BackgroundOption.allOptions) { option in
                            backgroundThumbnail(option)
                                .onTapGesture {
                                    HapticManager.light()
                                    selectedBackground = option
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 90)
            } else {
                Text("Background removal not available on this device")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .frame(height: 40)
            }
        }
        .onAppear { generateThumbnails() }
        .onChange(of: sourceImage) { _ in generateThumbnails() }
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private func backgroundThumbnail(_ option: BackgroundOption) -> some View {
        let isSelected = (option.id == selectedBackground.id)

        VStack(spacing: 4) {
            ZStack {
                if let thumb = thumbnails[option.id] {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if option.isOriginal, let source = sourceImage {
                    Image(uiImage: source)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    backgroundColorPreview(option)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 3)
            )

            Text(option.name)
                .font(.caption2)
                .foregroundColor(isSelected ? .purple : .white.opacity(0.7))
        }
    }

    /// Simple color swatch for options that haven't generated a thumbnail yet.
    @ViewBuilder
    private func backgroundColorPreview(_ option: BackgroundOption) -> some View {
        let view: some View = Group {
            switch option.type {
            case .solidColor(let color):
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(color))
                    .frame(width: 56, height: 56)
            case .gradient(let top, let bottom):
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color(top), Color(bottom)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 56, height: 56)
            case .blurred:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "camera.filters")
                            .foregroundColor(.white.opacity(0.5))
                    )
            default:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
            }
        }
        view
    }

    // MARK: - Thumbnail Generation

    private func generateThumbnails() {
        guard let image = sourceImage, !isGenerating else { return }
        isGenerating = true

        // Create a small thumbnail for faster segmentation
        let thumbSize = CGSize(width: 128, height: 128)
        guard let smallImage = image.preparingThumbnail(of: thumbSize) else {
            isGenerating = false
            return
        }

        Task.detached(priority: .userInitiated) {
            let removal = BackgroundRemoval()
            let options = BackgroundOption.allOptions.filter { !$0.isOriginal }

            // Try segmentation for each option
            do {
                let processed = try await withThrowingTaskGroup(
                    of: (String, UIImage).self
                ) { group -> [(String, UIImage)] in
                    for option in options {
                        group.addTask {
                            let result = try await removal.removeBackground(
                                from: smallImage,
                                replacement: option.type,
                                quality: .fast
                            )
                            return (option.id, result)
                        }
                    }
                    var pairs: [(String, UIImage)] = []
                    for try await pair in group {
                        pairs.append(pair)
                    }
                    return pairs
                }

                // Combine original + processed results
                let allPairs = [("original", smallImage)] + processed
                let newThumbnails = Dictionary(uniqueKeysWithValues: allPairs)
                await MainActor.run {
                    thumbnails = newThumbnails
                    isGenerating = false
                }
            } catch {
                // Segmentation failed — hide non-original options
                await MainActor.run {
                    segmentationAvailable = false
                    isGenerating = false
                }
            }
        }
    }
}
