import SwiftUI

/// Printer settings panel for the settings sheet.
///
/// Shows: default printer, paper size, copies, auto-print toggle.
/// Matches the dark theme of CameraSettingsPanel.
struct PrinterSettingsPanel: View {

    @EnvironmentObject var printService: PrintService

    var body: some View {
        VStack(spacing: 16) {
            // Printer selection
            printerRow

            Divider().background(Color.white.opacity(0.1))

            // Paper size chips
            paperSizeRow

            Divider().background(Color.white.opacity(0.1))

            // Copies stepper
            copiesRow

            Divider().background(Color.white.opacity(0.1))

            // Auto-print toggle
            autoPrintRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Printer Selection

    private var printerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Printer")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))

            HStack {
                Image(systemName: "printer.fill")
                    .foregroundColor(.cyan)
                    .frame(width: 28)

                if let printer = printService.defaultPrinter {
                    Text(printer.displayName)
                        .foregroundColor(.white)
                        .lineLimit(1)
                } else {
                    Text("No Printer Selected")
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                if printService.defaultPrinter != nil {
                    Button("Clear") {
                        HapticManager.light()
                        printService.clearDefaultPrinter()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }

                Button("Select") {
                    HapticManager.light()
                    Task { await printService.showPrinterPicker() }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.cyan.opacity(0.15))
                .cornerRadius(8)
            }
            .font(.subheadline)
        }
    }

    // MARK: - Paper Size

    private var paperSizeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Paper Size")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PaperSize.allCases, id: \.rawValue) { size in
                        paperSizeChip(size)
                            .onTapGesture {
                                HapticManager.light()
                                printService.setDefaultPaperSize(size)
                            }
                    }
                }
            }
        }
    }

    private func paperSizeChip(_ size: PaperSize) -> some View {
        let isSelected = size == printService.defaultPaperSize
        return Text(size.displayName)
            .font(.caption.weight(isSelected ? .bold : .regular))
            .foregroundColor(isSelected ? .cyan : .white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.cyan.opacity(0.15) : Color.white.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 1.5)
            )
    }

    // MARK: - Copies

    private var copiesRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Default Copies")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: {
                    if printService.defaultCopies > 1 {
                        HapticManager.light()
                        printService.setDefaultCopies(printService.defaultCopies - 1)
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(printService.defaultCopies > 1 ? .white : .gray)
                }
                .disabled(printService.defaultCopies <= 1)

                Text("\(printService.defaultCopies)")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundColor(.white)
                    .frame(width: 30)

                Button(action: {
                    if printService.defaultCopies < 10 {
                        HapticManager.light()
                        printService.setDefaultCopies(printService.defaultCopies + 1)
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(printService.defaultCopies < 10 ? .white : .gray)
                }
                .disabled(printService.defaultCopies >= 10)
            }
        }
    }

    // MARK: - Auto-Print

    private var autoPrintRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Print (Kiosk Mode)")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { printService.autoPrint },
                    set: { printService.setAutoPrint($0) }
                ))
                .labelsHidden()
                .tint(.cyan)
                .disabled(printService.defaultPrinter == nil)
            }

            if printService.defaultPrinter == nil {
                Text("Select a default printer first")
                    .font(.caption2)
                    .foregroundColor(.orange.opacity(0.7))
            } else if printService.autoPrint {
                Text("Photos will print automatically after each session")
                    .font(.caption2)
                    .foregroundColor(.cyan.opacity(0.7))
            }
        }
    }
}
