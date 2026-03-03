import Foundation

/// Builds the mobile-optimized HTML download page served to guests' phones.
///
/// All methods are pure functions — no state, no actor isolation.
nonisolated enum HTMLPageBuilder {

    /// Build the full HTML page for a photo download session.
    ///
    /// - Parameters:
    ///   - eventName: Event brand name shown at the top
    ///   - hashtag: Optional hashtag (include # character) shown below the photo
    ///   - imageURL: Relative URL of the preview JPEG (e.g., "/photo/{id}/image0.jpg")
    ///   - downloadURL: Relative URL for the download button (e.g., "/photo/{id}/download")
    ///   - photoCount: Number of photos available
    /// - Returns: Complete UTF-8 HTML string
    static func buildPage(
        eventName: String,
        hashtag: String?,
        imageURL: String,
        downloadURL: String,
        photoCount: Int
    ) -> String {
        let escapedName = htmlEscaped(eventName)
        let hashtagHTML = hashtag.map { "<p class=\"hashtag\">\(htmlEscaped($0))</p>" } ?? ""

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <meta name="theme-color" content="#000000">
          <meta name="apple-mobile-web-app-capable" content="yes">
          <title>\(escapedName) — Your Photo</title>
          <style>
            *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
            html, body {
              background: #000;
              color: #fff;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              min-height: 100svh;
              display: flex;
              flex-direction: column;
              align-items: center;
              padding: env(safe-area-inset-top, 20px) 16px env(safe-area-inset-bottom, 20px);
            }
            header {
              text-align: center;
              padding: 24px 0 16px;
              width: 100%;
            }
            header h1 {
              font-size: 1.4rem;
              font-weight: 700;
              letter-spacing: -0.02em;
            }
            header .subtitle {
              font-size: 0.85rem;
              color: rgba(255,255,255,0.55);
              margin-top: 4px;
            }
            .photo-card {
              width: 100%;
              max-width: 480px;
              background: #111;
              border-radius: 16px;
              overflow: hidden;
              margin: 8px 0;
              box-shadow: 0 8px 40px rgba(0,0,0,0.6);
            }
            .photo-card img {
              width: 100%;
              height: auto;
              display: block;
              -webkit-touch-callout: none;
              user-select: none;
            }
            .card-footer {
              padding: 16px;
              text-align: center;
            }
            .hashtag {
              color: #4FC3F7;
              font-size: 0.95rem;
              font-weight: 600;
              margin-bottom: 12px;
            }
            .btn-download {
              display: block;
              width: 100%;
              padding: 16px;
              background: #4FC3F7;
              color: #000;
              font-size: 1rem;
              font-weight: 700;
              text-decoration: none;
              border-radius: 12px;
              letter-spacing: 0.01em;
              transition: opacity 0.15s;
              -webkit-tap-highlight-color: transparent;
            }
            .btn-download:active { opacity: 0.75; }
            footer {
              margin-top: auto;
              padding-top: 24px;
              font-size: 0.75rem;
              color: rgba(255,255,255,0.35);
              text-align: center;
            }
          </style>
        </head>
        <body>
          <header>
            <h1>\(escapedName)</h1>
            <p class="subtitle">Your photobooth photo is ready!</p>
          </header>

          <div class="photo-card">
            <img src="\(imageURL)" alt="Your photobooth photo" draggable="false" loading="eager">
            <div class="card-footer">
              \(hashtagHTML)
              <a href="\(downloadURL)" class="btn-download" download>Save Photo</a>
            </div>
          </div>

          <footer>
            <p>Powered by PhotoBooth Pro</p>
          </footer>
        </body>
        </html>
        """
    }

    // MARK: - Private

    private static func htmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
