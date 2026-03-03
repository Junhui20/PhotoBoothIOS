import Foundation

/// Visual branding for the attract screen.
struct AttractBranding: Codable, Equatable, Sendable {
    var title: String = "PhotoBooth Pro"
    var subtitle: String = "Tap to Start"
    var primaryColorHex: String = "#00BFFF"       // Cyan
    var accentColorHex: String = "#FF69B4"        // Pink
}

/// A complete event profile with branding and session settings.
///
/// Operators create profiles for different events and switch between them.
/// Each profile stores attract screen branding and a full `SessionConfig`.
struct EventProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var branding: AttractBranding
    var config: SessionConfig
    var isDefault: Bool              // Built-in profiles cannot be deleted
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        branding: AttractBranding = AttractBranding(),
        config: SessionConfig = SessionConfig(),
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.branding = branding
        self.config = config
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Default Profiles

extension EventProfile {

    /// Built-in profiles created on first launch.
    static let defaults: [EventProfile] = [
        EventProfile(
            name: "Classic Dark",
            branding: AttractBranding(
                title: "PhotoBooth Pro",
                subtitle: "Tap to Start",
                primaryColorHex: "#00BFFF",
                accentColorHex: "#FFFFFF"
            ),
            config: SessionConfig(),
            isDefault: true
        ),
        EventProfile(
            name: "Elegant White",
            branding: AttractBranding(
                title: "Capture the Moment",
                subtitle: "Touch to Begin",
                primaryColorHex: "#F5F5F5",
                accentColorHex: "#C0A060"
            ),
            config: {
                var c = SessionConfig()
                c.layoutMode = .strip
                return c
            }(),
            isDefault: true
        ),
        EventProfile(
            name: "Party Neon",
            branding: AttractBranding(
                title: "Strike a Pose!",
                subtitle: "Tap for Fun",
                primaryColorHex: "#FF69B4",
                accentColorHex: "#00FF88"
            ),
            config: {
                var c = SessionConfig()
                c.captureMode = .boomerangGIF
                return c
            }(),
            isDefault: true
        ),
    ]
}
