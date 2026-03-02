import SwiftUI

/// Horizontal scrollable filter picker showing preview thumbnails.
///
/// Each thumbnail shows the current photo with a filter applied.
/// Tapping a thumbnail selects that filter.
struct FilterPickerView: View {

    let sourceImage: UIImage?
    @Binding var selectedFilter: PhotoFilter

    @State private var thumbnails: [String: UIImage] = [:]
    @State private var isGenerating = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PhotoFilter.allFilters) { filter in
                    filterThumbnail(filter)
                        .onTapGesture {
                            HapticManager.light()
                            selectedFilter = filter
                        }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 100)
        .onAppear { generateThumbnails() }
        .onChange(of: sourceImage) { _ in generateThumbnails() }
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private func filterThumbnail(_ filter: PhotoFilter) -> some View {
        let isSelected = (filter.id == selectedFilter.id)

        VStack(spacing: 4) {
            ZStack {
                if let thumb = thumbnails[filter.id] {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 64, height: 64)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.6)
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 3)
            )

            Text(filter.name)
                .font(.caption2)
                .foregroundColor(isSelected ? .cyan : .white.opacity(0.7))
        }
    }

    // MARK: - Thumbnail Generation

    private func generateThumbnails() {
        guard let image = sourceImage, !isGenerating else { return }
        isGenerating = true

        Task.detached(priority: .userInitiated) {
            let engine = FilterEngine.shared
            var results: [String: UIImage] = [:]

            for filter in PhotoFilter.allFilters {
                let thumb = engine.generateThumbnail(filter, from: image, size: CGSize(width: 128, height: 128))
                results[filter.id] = thumb
            }

            await MainActor.run {
                thumbnails = results
                isGenerating = false
            }
        }
    }
}
