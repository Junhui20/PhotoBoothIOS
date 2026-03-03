import SwiftUI

/// Form editor for an event profile's branding and session settings.
struct ProfileEditorView: View {

    @EnvironmentObject var profileManager: EventProfileManager
    @Environment(\.dismiss) private var dismiss

    /// Working copy — edits are not committed until Save is tapped.
    @State private var draft: EventProfile

    init(profile: EventProfile) {
        _draft = State(initialValue: profile)
    }

    var body: some View {
        NavigationView {
            Form {
                nameSection
                brandingSection
                sessionSection
                gifSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Profile Name") {
            TextField("Event Name", text: $draft.name)
        }
    }

    private var brandingSection: some View {
        Section("Attract Screen Branding") {
            TextField("Title", text: $draft.branding.title)
            TextField("Subtitle", text: $draft.branding.subtitle)

            ColorPicker(
                "Primary Color",
                selection: primaryColorBinding,
                supportsOpacity: false
            )

            ColorPicker(
                "Accent Color",
                selection: accentColorBinding,
                supportsOpacity: false
            )

            // Live preview
            brandingPreview
        }
    }

    private var sessionSection: some View {
        Section("Session Settings") {
            // Capture mode
            Picker("Capture Mode", selection: $draft.config.captureMode) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            // Layout mode (only for photo mode)
            if draft.config.captureMode == .photo {
                Picker("Layout", selection: $draft.config.layoutMode) {
                    ForEach(SessionConfig.LayoutMode.allCases, id: \.self) { layout in
                        Text(layout.rawValue.capitalized).tag(layout)
                    }
                }
            }

            Stepper(
                "Countdown: \(draft.config.countdownSeconds)s",
                value: $draft.config.countdownSeconds,
                in: 1...10
            )

            Stepper(
                "Review: \(Int(draft.config.reviewDuration))s",
                value: $draft.config.reviewDuration,
                in: 3.0...30.0
            )

            Stepper(
                "Auto Return: \(Int(draft.config.autoReturnDelay))s",
                value: $draft.config.autoReturnDelay,
                in: 10.0...120.0
            )

            Toggle("Auto-Save to Photos", isOn: $draft.config.autoSaveToPhotos)
            Toggle("Allow Retake", isOn: $draft.config.allowRetake)
            Toggle("Flash Effect", isOn: $draft.config.showFlashEffect)
            Toggle("Shutter Sound", isOn: $draft.config.playShutterSound)
            Toggle("Countdown Beep", isOn: $draft.config.playCountdownBeep)

            if draft.config.allowRetake {
                Stepper(
                    "Max Retakes: \(draft.config.maxRetakes)",
                    value: $draft.config.maxRetakes,
                    in: 1...10
                )
            }
        }
    }

    @ViewBuilder
    private var gifSection: some View {
        if draft.config.captureMode.isGIF {
            Section("GIF Settings") {
                Stepper(
                    "Frames: \(draft.config.gifFrameCount)",
                    value: $draft.config.gifFrameCount,
                    in: 8...24
                )

                Stepper(
                    "Interval: \(draft.config.gifFrameInterval)ms",
                    value: $draft.config.gifFrameInterval,
                    in: 40...200,
                    step: 10
                )

                let totalDuration = Double(draft.config.gifFrameCount * draft.config.gifFrameInterval) / 1000.0
                Text("Total capture time: \(String(format: "%.1f", totalDuration))s")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Branding Preview

    private var brandingPreview: some View {
        VStack(spacing: 8) {
            Text(draft.branding.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Color(UIColor(hex: draft.branding.primaryColorHex) ?? .cyan))

            Text(draft.branding.subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.black)
        .cornerRadius(8)
    }

    // MARK: - Color Bindings

    private var primaryColorBinding: Binding<Color> {
        Binding(
            get: { Color(UIColor(hex: draft.branding.primaryColorHex) ?? .cyan) },
            set: { newColor in
                draft.branding.primaryColorHex = UIColor(newColor).hexString
            }
        )
    }

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { Color(UIColor(hex: draft.branding.accentColorHex) ?? .systemPink) },
            set: { newColor in
                draft.branding.accentColorHex = UIColor(newColor).hexString
            }
        )
    }

    // MARK: - Save

    private func save() {
        profileManager.updateProfile(draft)
        dismiss()
    }
}
