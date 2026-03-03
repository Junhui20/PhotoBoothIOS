import UIKit
import os

// MARK: - Print Error

enum PrintError: LocalizedError, Sendable {
    case printingNotAvailable
    case printJobFailed(String)
    case insufficientPhotos(required: Int, provided: Int)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .printingNotAvailable:
            return "No AirPrint printer available."
        case .printJobFailed(let msg):
            return "Print failed: \(msg)"
        case .insufficientPhotos(let required, let provided):
            return "Need \(required) photos but only have \(provided)."
        case .renderFailed:
            return "Failed to render print layout."
        }
    }
}

// MARK: - Print Job Configuration

/// Immutable configuration for a print job.
struct PrintJobConfig: Sendable {
    let image: UIImage
    let paperSize: PaperSize
    let orientation: PrintOrientation
    let copies: Int
    let jobName: String

    init(
        image: UIImage,
        paperSize: PaperSize = .size4x6,
        orientation: PrintOrientation = .portrait,
        copies: Int = 1,
        jobName: String = "PhotoBooth Print"
    ) {
        self.image = image
        self.paperSize = paperSize
        self.orientation = orientation
        self.copies = copies
        self.jobName = jobName
    }
}

// MARK: - Print Service

/// Manages AirPrint printing via UIPrintInteractionController.
final class PrintService: ObservableObject {

    @Published var defaultPrinter: UIPrinter?
    @Published var printCount: Int = 0
    @Published var lastError: String?

    private let logger = Logger(subsystem: "com.photobooth.printing", category: "PrintService")

    /// Whether AirPrint is available on this device.
    var isPrintingAvailable: Bool {
        UIPrintInteractionController.isPrintingAvailable
    }

    // MARK: - Print

    /// Print an image via AirPrint.
    ///
    /// Uses the default printer if set (skips picker for kiosk mode).
    /// Otherwise shows the system print dialog.
    func printImage(config: PrintJobConfig) async -> Result<Bool, PrintError> {
        guard isPrintingAvailable else {
            return .failure(.printingNotAvailable)
        }

        let controller = UIPrintInteractionController.shared

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = config.jobName
        printInfo.outputType = .photo
        printInfo.orientation = config.orientation == .landscape ? .landscape : .portrait
        printInfo.duplex = .none

        controller.printInfo = printInfo
        controller.printingItem = config.image

        logger.info("Printing \(config.copies) copies on \(config.paperSize.displayName)")

        if let printer = defaultPrinter {
            return await printDirect(controller: controller, printer: printer, copies: config.copies)
        }

        return await presentDialog(controller: controller, copies: config.copies)
    }

    // MARK: - Default Printer

    /// Set a printer as default (skip picker on future prints).
    func setDefaultPrinter(_ printer: UIPrinter) {
        defaultPrinter = printer
        UserDefaults.standard.set(printer.url.absoluteString, forKey: "defaultPrinterURL")
        logger.info("Default printer set: \(printer.displayName)")
    }

    /// Clear the default printer.
    func clearDefaultPrinter() {
        defaultPrinter = nil
        UserDefaults.standard.removeObject(forKey: "defaultPrinterURL")
    }

    /// Restore default printer from UserDefaults (call on app launch).
    func restoreDefaultPrinter() {
        guard let urlString = UserDefaults.standard.string(forKey: "defaultPrinterURL"),
              let url = URL(string: urlString) else { return }
        defaultPrinter = UIPrinter(url: url)
    }

    // MARK: - Private

    private func printDirect(
        controller: UIPrintInteractionController,
        printer: UIPrinter,
        copies: Int
    ) async -> Result<Bool, PrintError> {
        await withCheckedContinuation { continuation in
            controller.print(to: printer) { [weak self] _, completed, error in
                Task { @MainActor [weak self] in
                    if completed {
                        self?.printCount += copies
                        self?.lastError = nil
                        continuation.resume(returning: .success(true))
                    } else if let error {
                        self?.lastError = error.localizedDescription
                        continuation.resume(returning: .failure(
                            .printJobFailed(error.localizedDescription)))
                    } else {
                        continuation.resume(returning: .success(false))
                    }
                }
            }
        }
    }

    private func presentDialog(
        controller: UIPrintInteractionController,
        copies: Int
    ) async -> Result<Bool, PrintError> {
        await withCheckedContinuation { continuation in
            controller.present(animated: true) { [weak self] _, completed, error in
                Task { @MainActor [weak self] in
                    if completed {
                        self?.printCount += copies
                        self?.lastError = nil
                        continuation.resume(returning: .success(true))
                    } else if let error {
                        self?.lastError = error.localizedDescription
                        continuation.resume(returning: .failure(
                            .printJobFailed(error.localizedDescription)))
                    } else {
                        continuation.resume(returning: .success(false))
                    }
                }
            }
        }
    }
}
