import Combine
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
///
/// Created at app level and injected via `.environmentObject()`.
/// Persists default printer, paper size, copies, and auto-print settings.
final class PrintService: ObservableObject {

    @Published var defaultPrinter: UIPrinter?
    @Published var defaultPaperSize: PaperSize = .size4x6
    @Published var defaultCopies: Int = 1
    @Published var autoPrint: Bool = false
    @Published var printCount: Int = 0
    @Published var lastError: String?

    private let logger = Logger(subsystem: "com.photobooth.printing", category: "PrintService")

    private enum Keys {
        static let printerURL = "defaultPrinterURL"
        static let paperSize = "defaultPaperSize"
        static let copies = "defaultCopies"
        static let autoPrint = "autoPrint"
    }

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

    // MARK: - Settings

    /// Set a printer as default (skip picker on future prints).
    func setDefaultPrinter(_ printer: UIPrinter) {
        defaultPrinter = printer
        UserDefaults.standard.set(printer.url.absoluteString, forKey: Keys.printerURL)
        logger.info("Default printer set: \(printer.displayName)")
    }

    /// Clear the default printer.
    func clearDefaultPrinter() {
        defaultPrinter = nil
        UserDefaults.standard.removeObject(forKey: Keys.printerURL)
        if autoPrint { setAutoPrint(false) }
    }

    func setDefaultPaperSize(_ size: PaperSize) {
        defaultPaperSize = size
        UserDefaults.standard.set(size.rawValue, forKey: Keys.paperSize)
    }

    func setDefaultCopies(_ count: Int) {
        let clamped = max(1, min(10, count))
        defaultCopies = clamped
        UserDefaults.standard.set(clamped, forKey: Keys.copies)
    }

    func setAutoPrint(_ enabled: Bool) {
        autoPrint = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.autoPrint)
    }

    /// Restore all persisted settings (call on app launch).
    func restoreDefaults() {
        // Printer
        if let urlString = UserDefaults.standard.string(forKey: Keys.printerURL),
           let url = URL(string: urlString) {
            defaultPrinter = UIPrinter(url: url)
        }
        // Paper size
        if let raw = UserDefaults.standard.string(forKey: Keys.paperSize),
           let size = PaperSize(rawValue: raw) {
            defaultPaperSize = size
        }
        // Copies
        let savedCopies = UserDefaults.standard.integer(forKey: Keys.copies)
        if savedCopies > 0 { defaultCopies = savedCopies }
        // Auto-print
        autoPrint = UserDefaults.standard.bool(forKey: Keys.autoPrint)
    }

    /// Show the AirPrint printer picker and set the selected printer as default.
    func showPrinterPicker() async -> Bool {
        let picker = UIPrinterPickerController(initiallySelectedPrinter: defaultPrinter)
        return await withCheckedContinuation { continuation in
            picker.present(animated: true) { [weak self] controller, completed, error in
                Task { @MainActor [weak self] in
                    if completed, let selected = controller.selectedPrinter {
                        self?.setDefaultPrinter(selected)
                        continuation.resume(returning: true)
                    } else {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
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
