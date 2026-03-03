import SwiftUI

// MARK: - Print Preview

/// Print preview screen showing the rendered layout with print controls.
///
/// Presented as a sheet from ShareView when user taps "Print".
struct PrintPreviewView: View {

    let photos: [UIImage]
    let textValues: [String: String]
    @EnvironmentObject var printService: PrintService

    @State private var selectedTemplate: PrintLayout = PrintTemplates.photoCard
    @State private var previewImage: UIImage?
    @State private var copies: Int = 1
    @State private var isPrinting = false
    @State private var printStatus: PrintStatus = .idle
    @State private var isGenerating = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    templateSelector
                    previewDisplay
                    printControls
                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("Print Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            copies = printService.defaultCopies
            selectBestTemplate()
            generatePreview()
        }
    }

    // MARK: - Template Selector

    private var templateSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(applicableTemplates) { template in
                    templateChip(template)
                        .onTapGesture {
                            HapticManager.light()
                            selectedTemplate = template
                            generatePreview()
                        }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 70)
    }

    @ViewBuilder
    private func templateChip(_ template: PrintLayout) -> some View {
        let isSelected = template.id == selectedTemplate.id
        VStack(spacing: 4) {
            Image(systemName: template.iconName)
                .font(.title2)
                .foregroundColor(isSelected ? .cyan : .white.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(isSelected ? Color.cyan.opacity(0.15) : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 2)
                )

            Text(template.name)
                .font(.caption2)
                .foregroundColor(isSelected ? .cyan : .white.opacity(0.5))
        }
    }

    /// Only show templates that match the current photo count.
    private var applicableTemplates: [PrintLayout] {
        PrintTemplates.all.filter { $0.requiredPhotoCount <= photos.count }
    }

    // MARK: - Preview Display

    @ViewBuilder
    private var previewDisplay: some View {
        if let image = previewImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
                .cornerRadius(8)
                .shadow(color: .white.opacity(0.05), radius: 15)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 300)
                .overlay(
                    Group {
                        if isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title2)
                                Text("Cannot render preview")
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.5))
                        }
                    }
                )
        }
    }

    // MARK: - Print Controls

    private var printControls: some View {
        VStack(spacing: 14) {
            // Paper size info
            HStack {
                Text("Paper")
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(selectedTemplate.paperSize.displayName) \(selectedTemplate.orientation == .landscape ? "Landscape" : "Portrait")")
                    .foregroundColor(.white)
            }
            .font(.subheadline)

            // Copies
            HStack {
                Text("Copies")
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                HStack(spacing: 16) {
                    Button(action: { if copies > 1 { copies -= 1 } }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(copies > 1 ? .white : .gray)
                    }
                    .disabled(copies <= 1)

                    Text("\(copies)")
                        .font(.title3.monospacedDigit().bold())
                        .foregroundColor(.white)
                        .frame(width: 30)

                    Button(action: { if copies < 10 { copies += 1 } }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(copies < 10 ? .white : .gray)
                    }
                    .disabled(copies >= 10)
                }
            }
            .font(.subheadline)

            // Printer
            HStack {
                Text("Printer")
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(printService.defaultPrinter?.displayName ?? "System Default")
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .font(.subheadline)

            // Print button
            Button(action: executePrint) {
                HStack(spacing: 8) {
                    if isPrinting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "printer.fill")
                    }
                    Text(isPrinting
                         ? "Printing..."
                         : "Print \(copies) \(copies == 1 ? "Copy" : "Copies")")
                }
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canPrint ? Color.blue : Color.gray.opacity(0.5))
                .cornerRadius(16)
            }
            .disabled(!canPrint)

            // Status message
            statusMessage
        }
    }

    private var canPrint: Bool {
        !isPrinting && printService.isPrintingAvailable && previewImage != nil
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch printStatus {
        case .idle:
            EmptyView()
        case .success:
            Label("Printed successfully!", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.subheadline)
        case .cancelled:
            Label("Print cancelled", systemImage: "xmark.circle")
                .foregroundColor(.yellow)
                .font(.subheadline)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.subheadline)
                .lineLimit(2)
        }
    }

    // MARK: - Actions

    private func selectBestTemplate() {
        // Find best template for the number of photos we have
        if let best = applicableTemplates.first(where: { $0.requiredPhotoCount == photos.count }) {
            selectedTemplate = best
        } else if let fallback = applicableTemplates.last {
            selectedTemplate = fallback
        }
    }

    private func generatePreview() {
        isGenerating = true
        let template = selectedTemplate
        let photosCopy = photos
        let textCopy = textValues

        Task.detached(priority: .userInitiated) {
            let result = PrintLayoutRenderer.shared.renderPreview(
                layout: template,
                photos: photosCopy,
                textValues: textCopy,
                maxWidth: 800
            )
            await MainActor.run {
                switch result {
                case .success(let image):
                    previewImage = image
                case .failure:
                    previewImage = nil
                }
                isGenerating = false
            }
        }
    }

    private func executePrint() {
        isPrinting = true
        printStatus = .idle

        let template = selectedTemplate
        let photosCopy = photos
        let textCopy = textValues
        let numCopies = copies

        Task {
            // Render at full 300 DPI
            let renderResult = await Task.detached(priority: .userInitiated) {
                PrintLayoutRenderer.shared.render(
                    layout: template,
                    photos: photosCopy,
                    textValues: textCopy,
                    dpi: 300
                )
            }.value

            switch renderResult {
            case .success(let printImage):
                let config = PrintJobConfig(
                    image: printImage,
                    paperSize: template.paperSize,
                    orientation: template.orientation,
                    copies: numCopies
                )
                let result = await printService.printImage(config: config)
                switch result {
                case .success(true):
                    printStatus = .success
                    HapticManager.success()
                case .success(false):
                    printStatus = .cancelled
                case .failure(let error):
                    printStatus = .failed(error.localizedDescription)
                }

            case .failure(let error):
                printStatus = .failed(error.localizedDescription)
            }

            isPrinting = false
        }
    }
}

// MARK: - Print Status

private enum PrintStatus {
    case idle
    case success
    case cancelled
    case failed(String)
}
