import SwiftUI

// MARK: - Camera Connection State

/// Represents the camera connection lifecycle with granular states for debugging.
enum CameraConnectionState: Equatable {
    case disconnected
    case searching
    case found(String)        // Camera USB device detected (device name)
    case openingSession       // PTP OpenSession sent, awaiting response
    case connected            // PTP session open, device info read
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected:         return "No Camera Connected"
        case .searching:            return "Searching for Camera…"
        case .found(let name):      return "Found: \(name)"
        case .openingSession:       return "Opening Session…"
        case .connected:            return "Camera Connected"
        case .error(let msg):       return "Error: \(msg)"
        }
    }

    var statusColor: Color {
        switch self {
        case .connected:                        return .green
        case .searching, .found, .openingSession: return .yellow
        case .disconnected, .error:             return .red
        }
    }

    var isReady: Bool {
        self == .connected
    }
}

// MARK: - Camera Device Info

/// Identity information read from the camera via PTP GetDeviceInfo.
struct CameraDeviceInfo {
    var name: String = ""
    var model: String = ""
    var manufacturer: String = ""
    var serialNumber: String = ""
    var firmwareVersion: String = ""
    var isConnected: Bool = false

    /// Best display name: prefer PTP model, fall back to ICDevice name.
    var displayName: String {
        if !model.isEmpty { return model }
        if !name.isEmpty { return name }
        return "Unknown Camera"
    }
}

// MARK: - Captured Photo

/// A photo captured from the camera and downloaded to the iPad.
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let imageData: Data
    let timestamp: Date
    let width: Int
    let height: Int

    var uiImage: UIImage? {
        UIImage(data: imageData)
    }
}

// MARK: - Errors

enum PhotoBoothError: LocalizedError {
    case cameraNotConnected
    case ptpCommandFailed(String)
    case ptpSessionOpenFailed(String)
    case deviceInfoParseFailed
    case noImagesFound
    case imageDownloadFailed
    case liveViewNotAvailable

    var errorDescription: String? {
        switch self {
        case .cameraNotConnected:
            return "No camera connected. Connect a Canon camera via USB."
        case .ptpCommandFailed(let msg):
            return "PTP command failed: \(msg)"
        case .ptpSessionOpenFailed(let msg):
            return "Failed to open camera session: \(msg)"
        case .deviceInfoParseFailed:
            return "Could not read camera device info."
        case .noImagesFound:
            return "No images found on camera."
        case .imageDownloadFailed:
            return "Failed to download image from camera."
        case .liveViewNotAvailable:
            return "Live view is not available on this camera."
        }
    }
}
