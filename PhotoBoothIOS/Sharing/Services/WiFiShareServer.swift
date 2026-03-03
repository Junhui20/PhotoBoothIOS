import Combine
import Foundation
import Network
import UIKit
import os

// MARK: - Server State

/// Observable state of the local WiFi sharing server.
enum WiFiShareServerState: Equatable {
    case idle
    case running(url: String, port: UInt16)
    case error(String)
}

// MARK: - WiFi Share Server

/// Runs a local HTTP server so guests can download photos by scanning a QR code.
///
/// Uses `NWListener` (Network.framework) on a private DispatchQueue.
/// Photos are held in memory only for the current session — no disk persistence.
///
/// Thread model:
/// - `NWListener` callbacks run on `serverQueue` (nonisolated)
/// - `@Published` properties updated via `Task { @MainActor in }`
/// - Same bridge pattern as `CameraManager` delegate callbacks
final class WiFiShareServer: ObservableObject, @unchecked Sendable {

    // MARK: - Published (MainActor)

    @Published var state: WiFiShareServerState = .idle
    @Published var shareURL: String = ""

    // MARK: - Private (serverQueue)

    private nonisolated let logger = Logger(
        subsystem: "com.photobooth.sharing", category: "WiFiShareServer"
    )
    private nonisolated let serverQueue = DispatchQueue(
        label: "photoboothios.wifiserver", qos: .utility
    )

    // Accessed only from serverQueue — nonisolated(unsafe) opts out of MainActor checking
    private nonisolated(unsafe) var listener: NWListener?
    private nonisolated(unsafe) var currentSessionID: String = ""
    private nonisolated(unsafe) var currentPhotos: [Data] = []
    private nonisolated(unsafe) var eventName: String = "PhotoBooth Pro"
    private nonisolated(unsafe) var hashtag: String?
    private nonisolated(unsafe) var isGIFSession: Bool = false

    // MARK: - Public API

    /// Start serving photos (or a GIF) for a new session.
    ///
    /// Tries port 8080 first; falls back to any available port.
    /// - Parameters:
    ///   - photos: JPEG data for each photo, or a single GIF data element
    ///   - sessionID: Unique session identifier (used in URL path)
    ///   - eventName: Brand name shown on download page
    ///   - hashtag: Optional hashtag shown on download page
    ///   - isGIF: When true, serves content as image/gif instead of image/jpeg
    func start(photos: [Data], sessionID: String, eventName: String, hashtag: String?, isGIF: Bool = false) {
        let photoData = photos
        let sid = sessionID
        let ename = eventName
        let tag = hashtag

        serverQueue.async { [weak self] in
            guard let self else { return }
            self.stopOnQueue()
            self.currentSessionID = sid
            self.currentPhotos = photoData
            self.eventName = ename
            self.hashtag = tag
            self.isGIFSession = isGIF
            self.startListenerOnQueue(preferredPort: 8080)
        }
    }

    /// Stop the server and clear session data.
    func stop() {
        serverQueue.async { [weak self] in
            self?.stopOnQueue()
        }
        Task { @MainActor in
            state = .idle
            shareURL = ""
        }
    }

    // MARK: - NWListener Lifecycle (serverQueue)

    private nonisolated func startListenerOnQueue(preferredPort: UInt16) {
        let port = NWEndpoint.Port(rawValue: preferredPort) ?? .any

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: port)
            self.listener = newListener

            newListener.stateUpdateHandler = { [weak self] listenerState in
                self?.handleListenerState(listenerState)
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            newListener.start(queue: serverQueue)
        } catch {
            if preferredPort != 0 {
                logger.warning("Port \(preferredPort) unavailable, trying random port")
                startListenerOnQueue(preferredPort: 0)
            } else {
                logger.error("NWListener init failed: \(error)")
                Task { @MainActor in
                    self.state = .error("Server could not start: \(error.localizedDescription)")
                }
            }
        }
    }

    private nonisolated func handleListenerState(_ listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            let port = listener?.port?.rawValue ?? 8080
            guard let ip = WiFiShareServer.localIPAddress() else {
                logger.error("Could not determine local IP address")
                Task { @MainActor in
                    self.state = .error("Could not determine WiFi IP address. Check WiFi connection.")
                }
                return
            }
            let sid = currentSessionID
            let url = "http://\(ip):\(port)/photo/\(sid)"
            logger.info("Server ready at \(url)")
            Task { @MainActor in
                self.shareURL = url
                self.state = .running(url: url, port: port)
            }

        case .failed(let error):
            logger.error("Listener failed: \(error)")
            Task { @MainActor in
                self.state = .error(error.localizedDescription)
            }

        case .cancelled:
            logger.info("Listener cancelled")

        default:
            break
        }
    }

    private nonisolated func stopOnQueue() {
        listener?.cancel()
        listener = nil
        currentPhotos = []
        currentSessionID = ""
        isGIFSession = false
    }

    // MARK: - Connection Handling (serverQueue)

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.logger.warning("Receive error: \(error)")
                connection.cancel()
                return
            }

            guard let data, !data.isEmpty,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            self.routeRequest(request, connection: connection)
        }
    }

    // MARK: - HTTP Router (serverQueue)

    private nonisolated func routeRequest(_ request: String, connection: NWConnection) {
        // Parse "GET /path HTTP/1.1"
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendResponse(connection: connection, status: "405 Method Not Allowed",
                         contentType: "text/plain", body: Data("Method Not Allowed".utf8))
            return
        }

        let path = parts[1]
        let basePath = "/photo/\(currentSessionID)"
        let photos = currentPhotos
        let isGIF = isGIFSession
        let fileExtension = isGIF ? ".gif" : ".jpg"
        let mimeType = isGIF ? "image/gif" : "image/jpeg"

        switch path {
        // HTML download page
        case basePath, basePath + "/":
            let photoIndex = max(0, photos.count - 1)
            let html = HTMLPageBuilder.buildPage(
                eventName: eventName,
                hashtag: hashtag,
                imageURL: "\(basePath)/image\(photoIndex)\(fileExtension)",
                downloadURL: "\(basePath)/download",
                photoCount: photos.count,
                isGIF: isGIF
            )
            sendResponse(connection: connection, status: "200 OK",
                         contentType: "text/html; charset=utf-8", body: Data(html.utf8))

        // Image preview: /photo/{id}/image0.jpg or /photo/{id}/image0.gif
        case _ where path.hasPrefix(basePath + "/image") && path.hasSuffix(fileExtension):
            let indexStr = path
                .replacingOccurrences(of: basePath + "/image", with: "")
                .replacingOccurrences(of: fileExtension, with: "")
            let index = Int(indexStr) ?? 0
            guard index >= 0, index < photos.count else {
                sendResponse(connection: connection, status: "404 Not Found",
                             contentType: "text/plain", body: Data("Not Found".utf8))
                return
            }
            sendResponse(connection: connection, status: "200 OK",
                         contentType: mimeType, body: photos[index])

        // Download with Content-Disposition: attachment
        case basePath + "/download":
            guard !photos.isEmpty else {
                sendResponse(connection: connection, status: "404 Not Found",
                             contentType: "text/plain", body: Data("No photo".utf8))
                return
            }
            let sid = currentSessionID
            sendDownloadResponse(
                connection: connection,
                fileData: photos[photos.count - 1],
                filename: "photobooth-\(sid.prefix(8))\(fileExtension)",
                contentType: mimeType
            )

        // Security: reject any path not matching current session
        default:
            sendResponse(connection: connection, status: "404 Not Found",
                         contentType: "text/plain", body: Data("Not Found".utf8))
        }
    }

    // MARK: - HTTP Response Helpers (serverQueue)

    private nonisolated func sendResponse(
        connection: NWConnection,
        status: String,
        contentType: String,
        body: Data
    ) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "\r\n"

        var responseData = Data(header.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error { self?.logger.warning("Send error: \(error)") }
            connection.cancel()
        })
    }

    private nonisolated func sendDownloadResponse(
        connection: NWConnection,
        fileData: Data,
        filename: String,
        contentType: String = "image/jpeg"
    ) {
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(fileData.count)\r\n"
        header += "Content-Disposition: attachment; filename=\"\(filename)\"\r\n"
        header += "Connection: close\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "\r\n"

        var responseData = Data(header.utf8)
        responseData.append(fileData)

        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error { self?.logger.warning("Download send error: \(error)") }
            connection.cancel()
        })
    }

    // MARK: - IP Address Detection

    /// Returns the device's WiFi (en0) IPv4 address using POSIX getifaddrs.
    /// Falls back to en1, then any non-loopback IPv4.
    nonisolated static func localIPAddress() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var candidates: [(priority: Int, address: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = flags & IFF_UP != 0
            let isLoopback = flags & IFF_LOOPBACK != 0

            if let addr = current.pointee.ifa_addr,
               isUp && !isLoopback && addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let name = String(cString: current.pointee.ifa_name)
                let ipStr = String(cString: hostname)
                let priority = name == "en0" ? 0 : (name == "en1" ? 1 : 2)
                candidates.append((priority, ipStr))
            }

            ptr = current.pointee.ifa_next
        }

        return candidates.sorted(by: { $0.priority < $1.priority }).first?.address
    }
}
