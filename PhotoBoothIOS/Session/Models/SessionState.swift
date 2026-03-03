import Foundation

/// The current phase of a photobooth session.
enum SessionPhase: Equatable {
    case attract        // Idle screen waiting for interaction
    case ready          // User tapped — brief "Get Ready!" screen
    case countdown(Int) // Counting down: 3, 2, 1
    case capturing      // Shutter firing, flash effect
    case processing     // Downloading & processing image
    case review         // Showing captured photo for approval
    case sharing        // Share/print options
    case complete       // Session done, returning to attract

    var allowsCapture: Bool {
        switch self {
        case .countdown(1): return true
        default: return false
        }
    }
}

/// Capture mode for a session.
nonisolated enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case photo          // Standard single/multi-photo capture
    case boomerangGIF   // Burst → forward+reverse loop GIF
    case burstGIF       // Burst → forward-only loop GIF

    var isGIF: Bool {
        self != .photo
    }

    var displayName: String {
        switch self {
        case .photo:        return "Photo"
        case .boomerangGIF: return "Boomerang"
        case .burstGIF:     return "Burst GIF"
        }
    }
}

/// Configuration for a photobooth session.
nonisolated struct SessionConfig: Codable, Equatable, Sendable {
    var countdownSeconds: Int = 3
    var photoCount: Int = 1
    var reviewDuration: TimeInterval = 8.0
    var autoReturnDelay: TimeInterval = 30.0
    var showFlashEffect: Bool = true
    var playShutterSound: Bool = true
    var playCountdownBeep: Bool = true
    var allowRetake: Bool = true
    var maxRetakes: Int = 3
    var autoSaveToPhotos: Bool = true
    var layoutMode: LayoutMode = .single

    // GIF capture settings
    var captureMode: CaptureMode = .photo
    var gifFrameCount: Int = 12        // Number of frames for GIF capture
    var gifFrameInterval: Int = 80     // Milliseconds between GIF frames

    enum LayoutMode: String, CaseIterable, Codable, Sendable {
        case single     // 1 photo
        case strip      // 3 photos vertical strip (2x6)
        case grid4      // 4 photos in grid (4x6)
        case duo        // 2 photos side by side

        var photoCount: Int {
            switch self {
            case .single: return 1
            case .duo:    return 2
            case .strip:  return 3
            case .grid4:  return 4
            }
        }
    }
}
