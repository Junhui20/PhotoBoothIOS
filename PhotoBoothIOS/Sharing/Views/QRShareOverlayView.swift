import SwiftUI

/// Fullscreen QR code overlay for photo download sharing.
///
/// Shows a large QR code encoding the local server URL.
/// Guests scan with their phone camera to open the download page.
/// Tap backdrop or X button to dismiss.
struct QRShareOverlayView: View {

    let shareURL: String
    let serverState: WiFiShareServerState
    let onClose: () -> Void

    @State private var qrImage: UIImage?
    @State private var showCopied = false

    var body: some View {
        ZStack {
            // Dark backdrop — tap to dismiss
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 24) {
                // Card
                VStack(spacing: 24) {
                    headerSection
                    qrCodeSection
                    urlSection
                    instructionText
                }
                .padding(32)
                .background(Color(white: 0.10))
                .cornerRadius(24)
                .shadow(color: .black.opacity(0.5), radius: 40)
                .padding(.horizontal, 32)
                // Prevent tap-through to backdrop
                .contentShape(Rectangle())
                .onTapGesture {}

                // Close button below card
                Button(action: {
                    HapticManager.light()
                    onClose()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 8)
            }
        }
        .task(id: shareURL) {
            guard !shareURL.isEmpty else { return }
            let url = shareURL
            let generated = await Task.detached(priority: .userInitiated) {
                QRCodeGenerator.generate(from: url, size: CGSize(width: 600, height: 600))
            }.value
            qrImage = generated
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Scan to Download")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Point your phone camera at the QR code")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var qrCodeSection: some View {
        switch serverState {
        case .idle:
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Starting server...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(width: 220, height: 220)

        case .running:
            if let qr = qrImage {
                Image(uiImage: qr)
                    .interpolation(.none)  // CRITICAL: nearest-neighbor for sharp QR pixels
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(12)
            } else {
                ProgressView().tint(.white)
                    .frame(width: 220, height: 220)
            }

        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(width: 220, height: 220)
        }
    }

    @ViewBuilder
    private var urlSection: some View {
        if case .running = serverState {
            Button(action: {
                UIPasteboard.general.string = shareURL
                showCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    showCopied = false
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: showCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(showCopied ? .green : .white.opacity(0.5))
                    Text(shareURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var instructionText: some View {
        Text("No app needed — opens in Safari or Chrome")
            .font(.caption)
            .foregroundColor(.white.opacity(0.4))
            .multilineTextAlignment(.center)
    }
}
