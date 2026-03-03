import SwiftUI

/// A single cell in the gallery grid showing a session thumbnail.
///
/// Displays the first photo's thumbnail, a relative date label,
/// and a photo count badge for multi-photo sessions.
struct GalleryThumbnailCell: View {

    let session: GallerySession
    let thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            // Thumbnail image
            ZStack(alignment: .topTrailing) {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                        .cornerRadius(10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 140)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.3))
                        )
                }

                // Photo count badge (multi-photo sessions)
                if session.photoCount > 1 {
                    Text("\(session.photoCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                        .padding(6)
                }
            }

            // Date label
            Text(relativeDate(session.timestamp))
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    // MARK: - Date Formatting

    private func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
