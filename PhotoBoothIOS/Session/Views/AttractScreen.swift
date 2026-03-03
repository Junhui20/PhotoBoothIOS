import SwiftUI

/// Idle/attract screen shown when no session is active.
///
/// Shows camera connection status and animated "Tap to Start" prompt.
/// Uses branding from the active event profile for title, subtitle, and colors.
/// Gallery/Settings pill buttons in top corners. Bottom status bar with battery.
struct AttractScreen: View {

    let isCameraReady: Bool
    let connectionText: String
    let branding: AttractBranding
    let profileName: String
    let cameraName: String
    let batteryLevel: Int
    let shotCount: Int
    let onStart: () -> Void
    let onSettings: () -> Void
    let onGallery: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var outerRingScale: CGFloat = 1.0

    private var primaryColor: Color {
        Color(UIColor(hex: branding.primaryColorHex) ?? .cyan)
    }

    private var batteryText: String {
        switch batteryLevel {
        case 0: return "Low!"
        case 1: return "Low"
        case 2: return "OK"
        case 3: return "Full"
        default: return "—"
        }
    }

    private var batteryIcon: String {
        switch batteryLevel {
        case 0: return "battery.0"
        case 1: return "battery.25"
        case 2: return "battery.50"
        case 3: return "battery.100"
        default: return "battery.0"
        }
    }

    private var batteryColor: Color {
        switch batteryLevel {
        case 0: return .red
        case 1: return .orange
        case 2, 3: return .green
        default: return .gray
        }
    }

    var body: some View {
        ZStack {
            // Overlay over live view (or solid dark when no camera)
            if isCameraReady {
                RadialGradient(
                    colors: [
                        Color.black.opacity(0.5),
                        Color.black.opacity(0.7),
                        Color.black.opacity(0.9)
                    ],
                    center: .center,
                    startRadius: 100,
                    endRadius: 500
                )
                .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [Color.black, Color(white: 0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            // Center content
            VStack(spacing: 32) {
                Spacer()

                // Event name badge
                Text(branding.title.uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(primaryColor)
                    .tracking(4)

                // Pulsing camera icon with concentric rings
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .fill(primaryColor.opacity(0.04))
                        .overlay(Circle().stroke(primaryColor.opacity(0.15), lineWidth: 2))
                        .frame(width: 180, height: 180)
                        .scaleEffect(outerRingScale)

                    // Middle ring
                    Circle()
                        .fill(primaryColor.opacity(0.06))
                        .overlay(Circle().stroke(primaryColor.opacity(0.25), lineWidth: 2))
                        .frame(width: 130, height: 130)

                    // Inner filled circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [primaryColor, primaryColor.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 90, height: 90)
                        .shadow(color: primaryColor.opacity(0.4), radius: 24, y: 8)
                        .scaleEffect(pulseScale)

                    // Camera icon
                    Image(systemName: "camera.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                        .scaleEffect(pulseScale)
                }
                .frame(width: 180, height: 180)

                // Tap to start text or connection status
                if isCameraReady {
                    VStack(spacing: 12) {
                        Text(branding.subtitle.uppercased())
                            .font(.system(size: 38, weight: .bold, design: .serif))
                            .foregroundColor(.white)

                        Text("Touch anywhere to begin your photo session")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.4))
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.yellow)
                            .scaleEffect(1.3)

                        Text(connectionText)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.yellow)

                        Text("Connect a Canon camera via USB to begin")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                Spacer()
                Spacer()
            }

            // Top bar (Gallery left, Settings right) + Bottom status bar
            VStack {
                HStack {
                    Button(action: onGallery) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 14))
                            Text("Gallery")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)
                    }

                    Spacer()

                    if isCameraReady {
                        Button(action: onSettings) {
                            HStack(spacing: 8) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 14))
                                Text("Settings")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)

                Spacer()

                // Bottom status bar
                if isCameraReady {
                    HStack {
                        // Left: connection status + camera name
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                            Text("Camera Connected")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.green)
                            Text("  \u{2022}  \(cameraName)")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.3))
                        }

                        Spacer()

                        // Right: battery + shot count
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: batteryIcon)
                                    .font(.system(size: 14))
                                    .foregroundColor(batteryColor)
                                Text(batteryText)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                            }

                            if shotCount > 0 {
                                Text("\u{2022}")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.3))
                                Text("\(shotCount) shots")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
                } else {
                    Text(profileName)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.bottom, 8)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isCameraReady {
                onStart()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.06
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                outerRingScale = 1.08
            }
        }
    }
}
