import SwiftUI
import UIKit

/// Presents a UIActivityViewController configured for AirDrop sharing.
///
/// On iPad, `UIActivityViewController` MUST have `popoverPresentationController`
/// configured or the app will crash. Pass the source button's global frame as `sourceRect`.
struct AirDropActivityView: UIViewControllerRepresentable {

    let images: [UIImage]
    let sourceRect: CGRect
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Only present once — guard against SwiftUI re-calling this
        guard uiViewController.presentedViewController == nil else { return }

        let activityVC = UIActivityViewController(
            activityItems: images,
            applicationActivities: nil
        )

        // Exclude everything except AirDrop
        activityVC.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .copyToPasteboard,
            .mail,
            .message,
            .openInIBooks,
            .postToFacebook,
            .postToFlickr,
            .postToTencentWeibo,
            .postToTwitter,
            .postToVimeo,
            .postToWeibo,
            .print,
            .saveToCameraRoll,
            .markupAsPDF,
        ]

        // iPad requires popover configuration — crash without this
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = uiViewController.view
            popover.sourceRect = sourceRect
            popover.permittedArrowDirections = [.up, .down]
        }

        let completionCallback = onComplete
        activityVC.completionWithItemsHandler = { _, completed, _, _ in
            completionCallback(completed)
        }

        // Present on next run loop tick to avoid SwiftUI update conflicts
        DispatchQueue.main.async {
            uiViewController.present(activityVC, animated: true)
        }
    }
}
