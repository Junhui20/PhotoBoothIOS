import SwiftUI

/// Detail view for a single gallery session.
///
/// Shows all photos from the session with options to re-share,
/// re-print, save to camera roll, or delete the session.
/// For GIF sessions, shows animated playback.
struct GallerySessionDetailView: View {

    let session: GallerySession

    @EnvironmentObject var galleryStore: GalleryStore
    @EnvironmentObject var printService: PrintService
    @EnvironmentObject var wifiServer: WiFiShareServer

    @Environment(\.dismiss) private var dismiss

    @State private var processedImages: [UIImage] = []
    @State private var gifFrames: [(image: UIImage, delay: TimeInterval)] = []
    @State private var gifData: Data?
    @State private var isLoading = true
    @State private var showDeleteAlert = false
    @State private var showPrintPreview = false
    @State private var showShareSheet = false
    @State private var savedToPhotos = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            } else if processedImages.isEmpty && gifFrames.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("Photos not found on disk")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        sessionHeader

                        if session.hasGIF {
                            gifPlayback
                        } else {
                            photoGrid
                        }

                        actionButtons
                        deleteButton
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadContent() }
        .onDisappear {
            processedImages = []
            gifFrames = []
            gifData = nil
        }
        .alert("Delete Session?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                galleryStore.deleteSession(session)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this session.")
        }
        .sheet(isPresented: $showPrintPreview) {
            PrintPreviewView(
                photos: processedImages,
                textValues: defaultTextValues
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if session.hasGIF, let data = gifData {
                GalleryShareSheet(
                    images: [],
                    sessionID: session.id,
                    gifData: data
                )
            } else {
                GalleryShareSheet(
                    images: processedImages,
                    sessionID: session.id
                )
            }
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        VStack(spacing: 8) {
            Text(formattedDate(session.timestamp))
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)

            HStack(spacing: 16) {
                if session.hasGIF {
                    Label(
                        session.captureMode == "boomerangGIF" ? "Boomerang" : "Burst GIF",
                        systemImage: "arrow.2.squarepath"
                    )
                } else {
                    Label("\(session.photoCount) photo\(session.photoCount == 1 ? "" : "s")",
                          systemImage: "photo")
                }
                if session.filterName != "natural" {
                    Label(session.filterName.capitalized, systemImage: "camera.filters")
                }
                if session.backgroundName != "Original" {
                    Label(session.backgroundName, systemImage: "rectangle.on.rectangle")
                }
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.5))

            if let data = gifData {
                Text(formatBytes(data.count))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    // MARK: - GIF Playback

    private var gifPlayback: some View {
        Group {
            if !gifFrames.isEmpty {
                AnimatedGIFView(
                    frames: gifFrames.map(\.image),
                    frameDuration: gifFrames.first?.delay ?? 0.08
                )
                .aspectRatio(contentMode: .fit)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.4), radius: 10)
            }
        }
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        VStack(spacing: 12) {
            ForEach(Array(processedImages.enumerated()), id: \.offset) { _, image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.4), radius: 10)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Save to Photos (only for non-GIF, or save first GIF frame)
            if !session.hasGIF {
                Button(action: saveToPhotos) {
                    Label(
                        savedToPhotos ? "Saved to Photos!" : "Save to Photos",
                        systemImage: savedToPhotos ? "checkmark.circle.fill" : "square.and.arrow.down"
                    )
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(savedToPhotos ? Color.green : Color.blue)
                    .cornerRadius(14)
                }
                .disabled(savedToPhotos)
            }

            HStack(spacing: 12) {
                // Re-Print (photo only)
                if !session.hasGIF {
                    Button(action: { showPrintPreview = true }) {
                        Label("Print", systemImage: "printer.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.25))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                            )
                    }
                }

                // Re-Share (AirDrop)
                Button(action: { showShareSheet = true }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.purple.opacity(0.25))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button(action: { showDeleteAlert = true }) {
            Label("Delete Session", systemImage: "trash")
                .font(.subheadline)
                .foregroundColor(.red.opacity(0.8))
        }
        .padding(.top, 8)
    }

    // MARK: - Loading

    private func loadContent() {
        isLoading = true
        let store = galleryStore
        let sid = session.id
        let count = session.photoCount
        let isGIF = session.hasGIF

        Task.detached {
            if isGIF {
                // Load GIF data and extract frames
                if let data = store.loadGIFData(sessionID: sid) {
                    let frames = GIFEncoder.extractFrames(from: data)
                    await MainActor.run {
                        gifData = data
                        gifFrames = frames
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        isLoading = false
                    }
                }
            } else {
                // Load processed images
                let loaded: [UIImage] = (0..<count).compactMap { i in
                    store.loadProcessedImage(sessionID: sid, index: i)
                }
                await MainActor.run {
                    processedImages = loaded
                    isLoading = false
                }
            }
        }
    }

    private func saveToPhotos() {
        PhotoLibraryHelper.saveMultipleToPhotos(processedImages) { success in
            if success {
                HapticManager.success()
                savedToPhotos = true
            }
        }
    }

    private var defaultTextValues: [String: String] {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return [
            "eventName": "PhotoBooth Pro",
            "date": formatter.string(from: session.timestamp),
        ]
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Gallery Share Sheet

/// Share sheet for re-sharing gallery photos or GIFs via AirDrop.
///
/// Uses a transparent host UIViewController so `popoverPresentationController`
/// has a valid `sourceView` on iPad (prevents crash).
struct GalleryShareSheet: UIViewControllerRepresentable {

    let images: [UIImage]
    let sessionID: UUID
    var gifData: Data? = nil

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard uiViewController.presentedViewController == nil else { return }

        // Share GIF file URL or images
        let items: [Any]
        if let data = gifData {
            // Write GIF to temp file so AirDrop sends a proper .gif file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("photobooth-\(sessionID.uuidString.prefix(8)).gif")
            try? data.write(to: tempURL)
            items = [tempURL]
        } else {
            items = images
        }

        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = uiViewController.view
            popover.sourceRect = CGRect(
                x: uiViewController.view.bounds.midX,
                y: uiViewController.view.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = [.up, .down]
        }

        DispatchQueue.main.async {
            uiViewController.present(activityVC, animated: true)
        }
    }
}
