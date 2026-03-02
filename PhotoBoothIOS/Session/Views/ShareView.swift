import SwiftUI

/// Share/complete screen with sharing options.
///
/// Placeholder for Task 06 — currently just "Save to Photos" and "Done" buttons.
/// Future: Print, Email, Text, QR Code, AirDrop.
struct ShareView: View {

    let photos: [CapturedPhoto]
    let onDone: () -> Void

    @State private var saved = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                Text("Share Your Photo")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Photo thumbnail
                if let photo = photos.last, let image = photo.uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(12)
                        .shadow(radius: 20)
                }

                // Sharing buttons
                VStack(spacing: 16) {
                    // Save to Photos (works now)
                    Button(action: saveToPhotos) {
                        Label(
                            saved ? "Saved!" : "Save to Photos",
                            systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down"
                        )
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 300)
                        .padding(.vertical, 16)
                        .background(saved ? Color.green : Color.blue)
                        .cornerRadius(16)
                    }
                    .disabled(saved)

                    // Future sharing options (placeholder)
                    HStack(spacing: 20) {
                        shareOptionButton(icon: "printer.fill", label: "Print")
                        shareOptionButton(icon: "envelope.fill", label: "Email")
                        shareOptionButton(icon: "qrcode", label: "QR Code")
                        shareOptionButton(icon: "square.and.arrow.up", label: "AirDrop")
                    }
                    .opacity(0.4) // Grayed out — not implemented yet
                }

                // Done button
                Button(action: {
                    HapticManager.light()
                    onDone()
                }) {
                    Text("Done")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 200)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(16)
                }
            }
            .padding(32)
        }
    }

    private func saveToPhotos() {
        for photo in photos {
            if let image = photo.uiImage {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
        HapticManager.success()
        saved = true
    }

    private func shareOptionButton(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}
