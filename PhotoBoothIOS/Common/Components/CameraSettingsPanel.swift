import SwiftUI

/// Bottom panel showing current camera settings as tappable chips.
/// Tapping a chip expands a horizontal value picker for that setting.
struct CameraSettingsPanel: View {

    @EnvironmentObject var cameraManager: CameraManager
    @Binding var activeSetting: SettingType?

    enum SettingType: Equatable {
        case iso, aperture, shutterSpeed, whiteBalance, exposureComp
    }

    var body: some View {
        VStack(spacing: 4) {
            chipsBar
            if let setting = activeSetting {
                pickerRow(for: setting)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeSetting)
    }

    // MARK: - Chips Bar

    private var chipsBar: some View {
        HStack(spacing: 10) {
            chip("ISO", cameraManager.cameraSettings.iso.displayName, .iso)
            chip(nil, cameraManager.cameraSettings.aperture.displayName, .aperture)
            chip(nil, cameraManager.cameraSettings.shutterSpeed.displayName, .shutterSpeed)
            chip("WB", cameraManager.cameraSettings.whiteBalance.displayName, .whiteBalance)
            chip("EV", cameraManager.cameraSettings.exposureComp.displayName, .exposureComp)
        }
        .padding(.horizontal, 12)
    }

    private func chip(_ prefix: String?, _ value: String, _ setting: SettingType) -> some View {
        Button {
            withAnimation {
                activeSetting = activeSetting == setting ? nil : setting
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
            .background(
                activeSetting == setting
                    ? Color.blue.opacity(0.6)
                    : Color.white.opacity(0.15)
            )
            .cornerRadius(16)
        }
    }

    // MARK: - Value Picker

    @ViewBuilder
    private func pickerRow(for setting: SettingType) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch setting {
                case .iso:
                    ForEach(ISOValue.selectable) { iso in
                        valueButton(
                            iso.displayName,
                            isSelected: iso == cameraManager.cameraSettings.iso
                        ) {
                            Task { try? await cameraManager.setISO(iso) }
                        }
                    }
                case .aperture:
                    ForEach(ApertureValue.selectable) { av in
                        valueButton(
                            av.displayName,
                            isSelected: av == cameraManager.cameraSettings.aperture
                        ) {
                            Task { try? await cameraManager.setAperture(av) }
                        }
                    }
                case .shutterSpeed:
                    ForEach(ShutterSpeedValue.selectable) { tv in
                        valueButton(
                            tv.displayName,
                            isSelected: tv == cameraManager.cameraSettings.shutterSpeed
                        ) {
                            Task { try? await cameraManager.setShutterSpeed(tv) }
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
                            Task { try? await cameraManager.setWhiteBalance(wb) }
                        }
                    }
                case .exposureComp:
                    ForEach(ExposureCompValue.allCases) { ev in
                        valueButton(
                            ev.displayName,
                            isSelected: ev == cameraManager.cameraSettings.exposureComp
                        ) {
                            Task { try? await cameraManager.setExposureComp(ev) }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
        .background(Color.black.opacity(0.6))
    }

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
}
