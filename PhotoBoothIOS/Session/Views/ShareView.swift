import SwiftUI

/// Share/complete screen with sharing options.
///
/// Print is functional (Task 05). Email, QR, AirDrop are placeholders for Task 06.
/// Supports auto-print in kiosk mode (prints automatically and advances).
struct ShareView: View {

    let photos: [CapturedPhoto]
    let selectedFilter: PhotoFilter
    let selectedBackground: BackgroundOption
    let onDone: () -> Void

    @EnvironmentObject var printService: PrintService

    @State private var saved = false
    @State private var showPrintPreview = false
    @State private var processedImages: [UIImage] = []
    @State private var isProcessing = false
    @State private var isAutoPrinting = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                Text("Share Your Photo")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Photo thumbnail (shows processed version if available)
                if let image = processedImages.last ?? photos.last?.uiImage {
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

            // Auto-print overlay
            if isAutoPrinting {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Printing...")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showPrintPreview) {
            PrintPreviewView(
                photos: processedImages.isEmpty ? photos.compactMap(\.uiImage) : processedImages,
                textValues: defaultTextValues
            )
        }
        .onAppear {
            processPhotos()
            if printService.autoPrint && printService.defaultPrinter != nil {
                triggerAutoPrint()
            }
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

    private func processPhotos() {
        let isNatural = (selectedFilter.id == "natural")
        let isOriginalBg = selectedBackground.isOriginal

        // Nothing to process — use originals
        if isNatural && isOriginalBg {
            processedImages = photos.compactMap(\.uiImage)
            return
        }

        isProcessing = true
        let photosCopy = photos
        let filter = selectedFilter
        let bgType = selectedBackground.type
        let needsBg = !isOriginalBg

        Task {
            let pipeline = ProcessingPipeline()
            var results: [UIImage] = []
            for photo in photosCopy {
                if let output = try? await pipeline.process(
                    photo: photo,
                    filter: filter,
                    background: needsBg ? bgType : nil
                ) {
                    results.append(output.displayImage)
                } else if let fallback = pipeline.applyFilterOnly(to: photo, filter: filter) {
                    results.append(fallback)
                }
            }
            processedImages = results
            isProcessing = false
        }
    }

    private func triggerAutoPrint() {
        isAutoPrinting = true
        let textCopy = defaultTextValues
        let paperSize = printService.defaultPaperSize
        let numCopies = printService.defaultCopies

        Task {
            // Wait for photo processing to finish
            while processedImages.isEmpty && isProcessing {
                try? await Task.sleep(for: .milliseconds(100))
            }

            let images = processedImages.isEmpty ? photos.compactMap(\.uiImage) : processedImages
            guard !images.isEmpty else {
                isAutoPrinting = false
                return
            }

            // Find best template for current photos
            let template = PrintTemplates.all
                .first(where: { $0.requiredPhotoCount <= images.count })
                ?? PrintTemplates.photoCard

            // Render at 300 DPI on background thread
            let renderResult = await Task.detached(priority: .userInitiated) {
                PrintLayoutRenderer.shared.render(
                    layout: template,
                    photos: images,
                    textValues: textCopy,
                    dpi: 300
                )
            }.value

            switch renderResult {
            case .success(let printImage):
                let config = PrintJobConfig(
                    image: printImage,
                    paperSize: paperSize,
                    orientation: template.orientation,
                    copies: numCopies
                )
                let result = await printService.printImage(config: config)
                isAutoPrinting = false

                if case .success(true) = result {
                    HapticManager.success()
                    try? await Task.sleep(for: .seconds(1.5))
                    onDone()
                }

            case .failure:
                isAutoPrinting = false
            }
        }
    }

    private func saveToPhotos() {
        let images = processedImages.isEmpty ? photos.compactMap(\.uiImage) : processedImages
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
