import SwiftUI

/// Share/complete screen with sharing options.
///
/// Print is functional (Task 05). Email, QR, AirDrop are placeholders for Task 06.
struct ShareView: View {

    let photos: [CapturedPhoto]
    let onDone: () -> Void

    @State private var saved = false
    @State private var showPrintPreview = false
    @StateObject private var printService = PrintService()

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
                    // Save to Photos
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

                    // Action buttons row
                    HStack(spacing: 20) {
                        // Print — functional
                        Button(action: { showPrintPreview = true }) {
                            VStack(spacing: 8) {
                                Image(systemName: "printer.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color.blue.opacity(0.3))
                                    .clipShape(Circle())
                                Text("Print")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }

                        // Placeholders — not implemented yet (Task 06)
                        shareOptionPlaceholder(icon: "envelope.fill", label: "Email")
                        shareOptionPlaceholder(icon: "qrcode", label: "QR Code")
                        shareOptionPlaceholder(icon: "square.and.arrow.up", label: "AirDrop")
                    }
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
        .sheet(isPresented: $showPrintPreview) {
            PrintPreviewView(
                photos: photos.compactMap(\.uiImage),
                textValues: defaultTextValues,
                printService: printService
            )
        }
    }

    // MARK: - Text Values

    private var defaultTextValues: [String: String] {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return [
            "eventName": "PhotoBooth Pro",
            "date": formatter.string(from: Date()),
        ]
    }

    // MARK: - Actions

    private func saveToPhotos() {
        let images = photos.compactMap(\.uiImage)
        PhotoLibraryHelper.saveMultipleToPhotos(images) { success in
            if success {
                HapticManager.success()
                saved = true
            }
        }
    }

    // MARK: - Placeholder Button

    private func shareOptionPlaceholder(icon: String, label: String) -> some View {
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
        .opacity(0.4)
    }
}
