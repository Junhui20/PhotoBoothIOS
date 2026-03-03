import UIKit

// MARK: - UIColor Hex Extension

nonisolated extension UIColor {
    /// Create a UIColor from a hex string like "#FF5733" or "FF5733".
    convenience init?(hex: String) {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }

        guard hexStr.count == 6,
              let rgb = UInt64(hexStr, radix: 16) else { return nil }

        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1.0
        )
    }
}
