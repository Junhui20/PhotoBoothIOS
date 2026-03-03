import SwiftUI

/// Share screen with functional Save, Print, QR Code, and AirDrop buttons.
///
/// Processes photos on appear (filter + background removal), then serves them
/// via a local WiFi server for QR code download and AirDrop sharing.
/// For GIF sessions, shares the GIF data directly.
struct ShareView: View {

    let photos: [CapturedPhoto]
    let selectedFilter: PhotoFilter
    let selectedBackground: BackgroundOption
    var gifData: Data? = nil
    let onDone: () -> Void

    @EnvironmentObject var printService: PrintService
    @EnvironmentObject var wifiServer: WiFiShareServer

    // MARK: - State

    @State private var saved = false
    @State private var showPrintPreview = false
    @State private var isProcessing = false
    @State private var isAutoPrinting = false

    // Full-res for printing
    @State private var processedImages: [UIImage] = []
    // 1920px share-optimized for AirDrop and QR
    @State private var shareImages: [UIImage] = []

    // AirDrop
    @State private var showAirDrop = false
    @State private var airDropShared = false
    @State private var airDropButtonRect: CGRect = .zero

    // QR
    @State private var showQROverlay = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                header
                photoThumbnail
                shareContent
                doneButton
            }
            .padding(32)

            // Auto-print overlay
            if isAutoPrinting {
                autoPrintOverlay
            }

            // QR overlay — fullscreen, tap to dismiss
            if showQROverlay {
                QRShareOverlayView(
                    shareURL: wifiServer.shareURL,
                    serverState: wifiServer.state,
                    onClose: {
                        HapticManager.light()
                        withAnimation(.easeOut(duration: 0.2)) {
                            showQROverlay = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            // AirDrop presenter — zero-size, anchored to button rect
            if showAirDrop {
                AirDropActivityView(
                    activityItems: airDropItems,
                    sourceRect: airDropButtonRect,
                    onComplete: { completed in
                        showAirDrop = false
                        if completed {
                            HapticManager.success()
                            airDropShared = true
                        }
                    }
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
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
            if !isGIFMode && printService.autoPrint && printService.defaultPrinter != nil {
                triggerAutoPrint()
            }
        }
    }

    // MARK: - Header

    private var isGIFMode: Bool { gifData != nil }

    private var header: some View {
        Text(isGIFMode ? "Share Your GIF" : "Share Your Photo")
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundColor(.white)
    }

    // MARK: - Photo Thumbnail

    @ViewBuilder
    private var photoThumbnail: some View {
        if isGIFMode, let data = gifData {
            // For GIF, show animated playback of the first frame
            let frames = GIFEncoder.extractFrames(from: data)
            if let firstImage = frames.first?.image {
                Image(uiImage: firstImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 280)
                    .cornerRadius(12)
                    .shadow(radius: 20)
                    .overlay(
                        Text("GIF")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.8))
                            .cornerRadius(6)
                            .padding(8),
                        alignment: .topTrailing
                    )
            }
        } else {
            let displayImage = shareImages.last ?? processedImages.last ?? photos.last?.uiImage
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 280)
                    .cornerRadius(12)
                    .shadow(radius: 20)
            }
        }
    }

    // MARK: - Share Content

    @ViewBuilder
    private var shareContent: some View {
        if !isGIFMode && isProcessing && processedImages.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                Text("Preparing your photo...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(minHeight: 160)
        } else {
            VStack(spacing: 16) {
                // Save to Photos — full-width primary button
                saveToPhotosButton

                // Action buttons — hide Print for GIF mode
                HStack(spacing: 16) {
                    if !isGIFMode {
                        printButton
                    }
                    qrCodeButton
                    airDropButton
                }
            }
        }
    }

    // MARK: - Buttons

    private var saveToPhotosButton: some View {
        Button(action: saveToPhotos) {
            Label(
                saved ? "Saved to Photos!" : "Save to Photos",
                systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down"
            )
            .font(.title3.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: 360)
            .padding(.vertical, 16)
            .background(saved ? Color.green : Color.blue)
            .cornerRadius(16)
        }
        .disabled(saved)
    }

    private var printButton: some View {
        ShareActionButton(
            icon: "printer.fill",
            label: "Print",
            color: .blue,
            isActive: false
        ) {
            HapticManager.light()
            showPrintPreview = true
        }
    }

    private var qrCodeButton: some View {
        ShareActionButton(
            icon: "qrcode",
            label: "QR Code",
            color: .purple,
            isActive: showQROverlay
        ) {
            HapticManager.light()
            withAnimation(.easeIn(duration: 0.2)) {
                showQROverlay = true
            }
        }
        .disabled(wifiServer.state == .idle)
    }

    private var airDropButton: some View {
        ShareActionButton(
            icon: airDropShared ? "checkmark.circle.fill" : "square.and.arrow.up",
            label: airDropShared ? "Shared!" : "AirDrop",
            color: airDropShared ? .green : .cyan,
            isActive: showAirDrop
        ) {
            guard isGIFMode ? (gifData != nil) : (!shareImages.isEmpty || !processedImages.isEmpty) else { return }
            HapticManager.light()
            showAirDrop = true
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { airDropButtonRect = geo.frame(in: .global) }
                    .onChange(of: geo.size) { _ in
                        airDropButtonRect = geo.frame(in: .global)
                    }
            }
        )
    }

    private var doneButton: some View {
        Button(action: {
            HapticManager.light()
            wifiServer.stop()
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

    // MARK: - Auto-Print Overlay

    private var autoPrintOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(.white).scaleEffect(1.5)
                Text("Printing...")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
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

    // MARK: - AirDrop Items

    /// Items to share via AirDrop — GIF file URL for GIF mode, images otherwise.
    private var airDropItems: [Any] {
        if isGIFMode, let data = gifData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("photobooth-share.gif")
            try? data.write(to: tempURL)
            return [tempURL]
        } else {
            let images: [UIImage] = shareImages.isEmpty ? processedImages : shareImages
            return images
        }
    }

    // MARK: - Photo Processing

    private func processPhotos() {
        // GIF mode — no image processing needed, just start WiFi server
        if isGIFMode {
            startWiFiServer()
            return
        }

        let isNatural = (selectedFilter.id == "natural")
        let isOriginalBg = selectedBackground.isOriginal

        // Nothing to process — use originals
        if isNatural && isOriginalBg {
            let originals = photos.compactMap(\.uiImage)
            processedImages = originals
            let pipeline = ProcessingPipeline()
            shareImages = originals.map { pipeline.resizeForSharing($0, maxDimension: 1920) }
            startWiFiServer()
            return
        }

        isProcessing = true
        let photosCopy = photos
        let filter = selectedFilter
        let bgType = selectedBackground.type
        let needsBg = !isOriginalBg

        Task {
            let pipeline = ProcessingPipeline()
            var fullRes: [UIImage] = []
            var shares: [UIImage] = []

            for photo in photosCopy {
                if let output = try? await pipeline.process(
                    photo: photo,
                    filter: filter,
                    background: needsBg ? bgType : nil
                ) {
                    fullRes.append(output.displayImage)
                    shares.append(output.shareImage)
                } else if let fallback = pipeline.applyFilterOnly(to: photo, filter: filter) {
                    fullRes.append(fallback)
                    shares.append(pipeline.resizeForSharing(fallback, maxDimension: 1920))
                }
            }

            processedImages = fullRes
            shareImages = shares
            isProcessing = false
            startWiFiServer()
        }
    }

    // MARK: - WiFi Server

    private func startWiFiServer() {
        let sessionID = UUID().uuidString

        // GIF mode — serve the GIF data directly
        if isGIFMode, let data = gifData {
            wifiServer.start(
                photos: [data],
                sessionID: sessionID,
                eventName: "PhotoBooth Pro",
                hashtag: nil,
                isGIF: true
            )
            return
        }

        // Photo mode — serve JPEG data
        let images = shareImages.isEmpty ? processedImages : shareImages
        guard !images.isEmpty else { return }

        var jpegDataArray: [Data] = []
        for image in images {
            if let jpeg = image.jpegData(compressionQuality: 0.88) {
                jpegDataArray.append(jpeg)
            }
        }
        guard !jpegDataArray.isEmpty else { return }

        wifiServer.start(
            photos: jpegDataArray,
            sessionID: sessionID,
            eventName: "PhotoBooth Pro",
            hashtag: nil
        )
    }

    // MARK: - Actions

    private func saveToPhotos() {
        if isGIFMode, let data = gifData {
            // Save GIF to temp file, then save to Photos
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("photobooth-\(UUID().uuidString).gif")
            do {
                try data.write(to: tempURL)
                PhotoLibraryHelper.saveGIFToPhotos(tempURL) { success in
                    if success {
                        HapticManager.success()
                        saved = true
                    }
                }
            } catch {
                // GIF write failed — skip save
            }
            return
        }

        let images = processedImages.isEmpty ? photos.compactMap(\.uiImage) : processedImages
        PhotoLibraryHelper.saveMultipleToPhotos(images) { success in
            if success {
                HapticManager.success()
                saved = true
            }
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

            let template = PrintTemplates.all
                .first(where: { $0.requiredPhotoCount <= images.count })
                ?? PrintTemplates.photoCard

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
                    wifiServer.stop()
                    onDone()
                }

            case .failure:
                isAutoPrinting = false
            }
        }
    }
}

// MARK: - Share Action Button

/// Reusable icon + label button for the share action grid.
private struct ShareActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(isActive ? color : color.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(color.opacity(isActive ? 1.0 : 0.4), lineWidth: 1.5)
                    )

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
