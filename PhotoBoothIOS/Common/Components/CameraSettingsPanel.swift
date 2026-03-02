import SwiftUI

/// Bottom panel showing current camera settings as tappable chips.
///
/// Two modes:
///   - **Auto**: Read-only display of current camera values. No picker.
///   - **Manual**: Tapping a chip expands a horizontal value picker.
///     Only shows values the camera/lens/mode currently supports (from 0xC18A events).
struct CameraSettingsPanel: View {

    @EnvironmentObject var cameraManager: CameraManager
    @Binding var activeSetting: SettingType?
    @Binding var isManualMode: Bool
    @State private var errorMessage: String?

    enum SettingType: Equatable {
        case iso, aperture, shutterSpeed, whiteBalance, exposureComp
    }

    var body: some View {
        VStack(spacing: 4) {
            modeToggle
            chipsBar

            if isManualMode, let setting = activeSetting {
                pickerRow(for: setting)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Error message (briefly shown when camera rejects a value)
            if let error = errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeSetting)
        .animation(.easeInOut(duration: 0.2), value: isManualMode)
        .animation(.easeInOut(duration: 0.3), value: errorMessage)
        .onChange(of: isManualMode) { newValue in
            if !newValue {
                activeSetting = nil
                errorMessage = nil
            }
        }
    }

    // MARK: - Auto / Manual Toggle

    private var modeToggle: some View {
        HStack(spacing: 12) {
            // Camera dial mode badge (A+, P, Tv, Av, M, Fv)
            if cameraManager.cameraSettings.shootingMode != .unknown {
                Text(cameraManager.cameraSettings.shootingMode.displayName)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
            }

            Spacer()

            // Auto / Manual segmented toggle
            HStack(spacing: 0) {
                modeButton("Auto", isActive: !isManualMode) {
                    isManualMode = false
                }
                modeButton("Manual", isActive: isManualMode) {
                    isManualMode = true
                }
            }
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal, 12)
    }

    private func modeButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isActive ? .bold : .regular)
                .foregroundColor(isActive ? .black : .white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isActive ? Color.yellow : Color.clear)
                .cornerRadius(8)
        }
    }

    // MARK: - Chips Bar

    private var chipsBar: some View {
        HStack(spacing: 10) {
            chip("ISO", cameraManager.cameraSettings.iso.displayName, .iso)
            chip("Av", cameraManager.cameraSettings.aperture.displayName, .aperture)
            chip("Tv", cameraManager.cameraSettings.shutterSpeed.displayName, .shutterSpeed)
            chip("WB", cameraManager.cameraSettings.whiteBalance.displayName, .whiteBalance)
            chip("EV", cameraManager.cameraSettings.exposureComp.displayName, .exposureComp)
        }
        .padding(.horizontal, 12)
    }

    private func chip(_ prefix: String?, _ value: String, _ setting: SettingType) -> some View {
        Button {
            guard isManualMode else { return }
            withAnimation {
                activeSetting = activeSetting == setting ? nil : setting
                errorMessage = nil
            }
        } label: {
            HStack(spacing: 2) {
                if let prefix {
                    Text(prefix)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chipBackground(for: setting))
            .cornerRadius(16)
        }
        .disabled(!isManualMode)
    }

    private func chipBackground(for setting: SettingType) -> Color {
        if isManualMode && activeSetting == setting {
            return Color.blue.opacity(0.6)
        }
        return Color.white.opacity(isManualMode ? 0.15 : 0.08)
    }

    // MARK: - Value Picker

    @ViewBuilder
    private func pickerRow(for setting: SettingType) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch setting {
                case .iso:
                    ForEach(availableISOs) { iso in
                        valueButton(
                            iso.displayName,
                            isSelected: iso == cameraManager.cameraSettings.iso
                        ) {
                            applySetting { try await cameraManager.setISO(iso) }
                        }
                    }
                case .aperture:
                    ForEach(availableApertures) { av in
                        valueButton(
                            av.displayName,
                            isSelected: av == cameraManager.cameraSettings.aperture
                        ) {
                            applySetting { try await cameraManager.setAperture(av) }
                        }
                    }
                case .shutterSpeed:
                    ForEach(availableShutterSpeeds) { tv in
                        valueButton(
                            tv.displayName,
                            isSelected: tv == cameraManager.cameraSettings.shutterSpeed
                        ) {
                            applySetting { try await cameraManager.setShutterSpeed(tv) }
                        }
                    }
                case .whiteBalance:
                    ForEach(WhiteBalanceValue.selectable) { wb in
                        HStack(spacing: 4) {
                            Image(systemName: wb.iconName)
                                .font(.caption2)
                            Text(wb.displayName)
                                .font(.caption)
                        }
                        .fontWeight(wb == cameraManager.cameraSettings.whiteBalance ? .bold : .regular)
                        .foregroundColor(wb == cameraManager.cameraSettings.whiteBalance ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            wb == cameraManager.cameraSettings.whiteBalance
                                ? Color.yellow : Color.white.opacity(0.2)
                        )
                        .cornerRadius(14)
                        .onTapGesture {
                            applySetting { try await cameraManager.setWhiteBalance(wb) }
                        }
                    }
                case .exposureComp:
                    ForEach(availableExposureComps) { ev in
                        valueButton(
                            ev.displayName,
                            isSelected: ev == cameraManager.cameraSettings.exposureComp
                        ) {
                            applySetting { try await cameraManager.setExposureComp(ev) }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
        .background(Color.black.opacity(0.6))
    }

    // MARK: - Available Values (from camera, or fallback to all)

    private var availableISOs: [ISOValue] {
        let list = cameraManager.cameraSettings.availableISOs
        return list.isEmpty ? ISOValue.selectable : list
    }

    private var availableApertures: [ApertureValue] {
        let list = cameraManager.cameraSettings.availableApertures
        return list.isEmpty ? ApertureValue.selectable : list
    }

    private var availableShutterSpeeds: [ShutterSpeedValue] {
        let list = cameraManager.cameraSettings.availableShutterSpeeds
        return list.isEmpty ? ShutterSpeedValue.selectable : list
    }

    private var availableExposureComps: [ExposureCompValue] {
        let list = cameraManager.cameraSettings.availableExposureComps
        return list.isEmpty ? ExposureCompValue.allCases : list
    }

    // MARK: - Helpers

    private func valueButton(
        _ label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.yellow : Color.white.opacity(0.2))
                .cornerRadius(14)
        }
    }

    /// Apply a setting change and show error if camera rejects it.
    private func applySetting(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                errorMessage = nil
            } catch {
                errorMessage = "Camera rejected: \(error.localizedDescription)"
                // Auto-dismiss after 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    errorMessage = nil
                }
            }
        }
    }
}
