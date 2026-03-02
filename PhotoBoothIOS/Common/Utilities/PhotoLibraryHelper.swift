import Photos
import UIKit

/// Centralized photo library save with permission handling.
///
/// Always request authorization before saving — avoids silent failures
/// when `NSPhotoLibraryAddUsageDescription` is present but user hasn't granted access.
enum PhotoLibraryHelper {

    /// Save a UIImage to the photo library, requesting permission first if needed.
    ///
    /// - Parameters:
    ///   - image: The image to save
    ///   - completion: Called on MainActor with success/failure
    static func saveToPhotos(_ image: UIImage, completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in completion?(false) }
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            Task { @MainActor in completion?(true) }
        }
    }

    /// Save multiple images to the photo library.
    static func saveMultipleToPhotos(_ images: [UIImage], completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in completion?(false) }
                return
            }
            for image in images {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
            Task { @MainActor in completion?(true) }
        }
    }
}
