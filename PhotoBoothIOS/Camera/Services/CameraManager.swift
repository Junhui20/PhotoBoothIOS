import Combine
import Foundation
import ImageCaptureCore
import UIKit
import os

/// Manages Canon camera discovery and PTP communication over USB.
///
/// Create exactly ONE instance at app level and inject via `.environmentObject()`.
/// This class is MainActor-isolated by default (project setting).
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var connectionState: CameraConnectionState = .disconnected
    @Published var deviceInfo = CameraDeviceInfo()
    @Published var liveViewImage: UIImage?
    @Published var lastCapturedPhoto: CapturedPhoto?
    @Published var isCapturing: Bool = false
    @Published var isLiveViewActive: Bool = false

    // MARK: - Private

    private nonisolated let logger = Logger(subsystem: "com.instamedia.photoboothios", category: "CameraManager")
    private var deviceBrowser: ICDeviceBrowser?
    private var cameraDevice: ICCameraDevice?
    private var transactionID: UInt32 = 0
    private var liveViewTask: Task<Void, Never>?

    // MARK: - Lifecycle

    override init() {
        super.init()
    }

    /// Start scanning for USB cameras.
    /// Requests iOS 14+ control authorization first, then starts the device browser.
    func startScanning() {
        guard deviceBrowser == nil else {
            logger.info("Already scanning")
            return
        }

        logger.info("Starting camera scan…")
        connectionState = .searching

        let browser = ICDeviceBrowser()
        browser.delegate = self
        // Bug #5 fix: only USB-connected cameras (.local), not network (.bonjour)
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue:
            ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        )!
        deviceBrowser = browser

        // iOS 14+: Must request control authorization before camera will respond
        let controlStatus = browser.controlAuthorizationStatus
        logger.info("Control authorization status: \(String(describing: controlStatus))")

        if controlStatus == .notDetermined {
            browser.requestControlAuthorization { status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.logger.info("Control authorization result: \(String(describing: status))")
                    if status == .authorized {
                        browser.start()
                        self.logger.info("Device browser started after authorization")
                    } else {
                        self.connectionState = .error("Camera control permission denied")
                        self.logger.error("Camera control authorization denied")
                    }
                }
            }
        } else if controlStatus == .authorized {
            browser.start()
            logger.info("Device browser started (already authorized)")
        } else {
            connectionState = .error("Camera control permission denied")
            logger.error("Camera control not authorized: \(String(describing: controlStatus))")
        }
    }

    /// Stop scanning and disconnect.
    func stopScanning() {
        stopLiveView()
        deviceBrowser?.stop()
        deviceBrowser = nil
        cameraDevice?.requestCloseSession()
        cameraDevice?.delegate = nil
        cameraDevice = nil
        transactionID = 0
        connectionState = .disconnected
        deviceInfo = CameraDeviceInfo()
        liveViewImage = nil
        lastCapturedPhoto = nil
    }

    // MARK: - PTP Transaction ID

    private func nextTransactionID() -> UInt32 {
        transactionID += 1
        return transactionID
    }

    // MARK: - PTP Command Sending

    /// Send a PTP command and return the response data.
    /// Bug #2 fix: uses `ptpResponseData ?? responseData` to capture actual payload.
    func sendPTPCommand(
        opCode: UInt16,
        params: [UInt32] = [],
        outData: Data? = nil
    ) async throws -> Data {
        guard let camera = cameraDevice else {
            throw PhotoBoothError.cameraNotConnected
        }

        let txID = nextTransactionID()
        let commandData = CanonPTP.buildCommand(
            opCode: opCode,
            transactionID: txID,
            params: params
        )

        logger.debug("PTP TX [0x\(String(opCode, radix: 16))] txID=\(txID) cmd=\(commandData.hexPrefix(32))")

        return try await withCheckedThrowingContinuation { continuation in
            camera.requestSendPTPCommand(
                commandData,
                outData: outData ?? Data()
            ) { [weak self] responseData, ptpResponseData, error in
                if let error {
                    self?.logger.error("PTP error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }

                // Bug #2 fix: prefer ptpResponseData (actual payload) over responseData (PTP header)
                let data = ptpResponseData.isEmpty ? responseData : ptpResponseData

                self?.logger.debug("PTP RX [\(data.count) bytes] \(data.hexPrefix(64))")

                if responseData.count >= 8 {
                    let respCode = responseData.readUInt16(at: 6)
                    self?.logger.debug("PTP response code: 0x\(String(respCode, radix: 16))")
                }

                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - Device Info Reading

    /// Read and parse camera identity via PTP GetDeviceInfo (0x1001).
    func readDeviceInfo() async {
        do {
            let data = try await sendPTPCommand(opCode: CanonPTP.OpCode.getDeviceInfo.rawValue)

            logger.info("GetDeviceInfo response: \(data.count) bytes")

            if let info = CanonPTP.parseDeviceInfo(from: data) {
                deviceInfo.model = info.model
                deviceInfo.manufacturer = info.manufacturer
                deviceInfo.serialNumber = info.serialNumber
                deviceInfo.firmwareVersion = info.deviceVersion
                deviceInfo.isConnected = true

                logger.info("Camera identified — Model: \(info.model), Manufacturer: \(info.manufacturer), Serial: \(info.serialNumber), Firmware: \(info.deviceVersion)")
            } else {
                logger.warning("Could not parse DeviceInfo, using ICDevice name as fallback")
                deviceInfo.isConnected = true
            }

            connectionState = .connected

        } catch {
            logger.error("GetDeviceInfo failed: \(error.localizedDescription)")
            deviceInfo.isConnected = true
            connectionState = .connected
        }
    }

    // MARK: - Remote Mode Setup

    /// Enable remote shooting mode on the camera.
    /// Canon EOS cameras require this before accepting remote commands.
    /// Sequence: SetRemoteMode → SetEventMode → GetEvent (drain pending).
    func enableRemoteMode() async {
        logger.info("Enabling remote shooting mode…")

        // Step 1: SetRemoteMode (0x9114) — 0x15 for newer mirrorless, fallback 0x01
        do {
            _ = try await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.setRemoteMode.rawValue,
                params: [0x15]
            )
            logger.info("SetRemoteMode(0x15) succeeded")
        } catch {
            logger.warning("SetRemoteMode(0x15) failed, trying 0x01: \(error.localizedDescription)")
            do {
                _ = try await sendPTPCommand(
                    opCode: CanonPTP.CanonOpCode.setRemoteMode.rawValue,
                    params: [0x01]
                )
                logger.info("SetRemoteMode(0x01) succeeded")
            } catch {
                logger.error("SetRemoteMode failed entirely: \(error.localizedDescription)")
            }
        }

        // Step 2: SetEventMode (0x9115) — enable event notifications
        do {
            _ = try await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.setEventMode.rawValue,
                params: [0x01]
            )
            logger.info("SetEventMode(1) succeeded")
        } catch {
            logger.warning("SetEventMode failed (non-fatal): \(error.localizedDescription)")
        }

        // Step 3: Drain any pending events
        _ = try? await sendPTPCommand(
            opCode: CanonPTP.CanonOpCode.getEvent.rawValue
        )
        logger.info("Remote mode setup complete")
    }

    // MARK: - Live View

    /// Start live view streaming from the camera viewfinder.
    func startLiveView() {
        guard connectionState.isReady, cameraDevice != nil else {
            logger.warning("Cannot start live view — camera not connected")
            return
        }
        guard liveViewTask == nil else {
            logger.info("Live view already running")
            return
        }

        isLiveViewActive = true
        logger.info("Starting live view…")

        liveViewTask = Task { [weak self] in
            guard let self else { return }
            await self.liveViewLoop()
        }
    }

    /// Stop live view streaming.
    func stopLiveView() {
        isLiveViewActive = false
        liveViewTask?.cancel()
        liveViewTask = nil

        // Tell camera to stop viewfinder (fire-and-forget)
        if cameraDevice != nil {
            Task {
                _ = try? await sendPTPCommand(
                    opCode: CanonPTP.CanonOpCode.terminateViewfinder.rawValue
                )
                logger.info("Viewfinder terminated")
            }
        }
    }

    /// Internal live view polling loop.
    private func liveViewLoop() async {
        // Step 1: Initiate viewfinder on camera
        do {
            _ = try await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.initViewfinder.rawValue
            )
            logger.info("InitViewfinder (0x9151) succeeded")
        } catch {
            logger.warning("InitViewfinder failed (trying to poll anyway): \(error.localizedDescription)")
        }

        // Brief delay for camera to prepare
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Step 2: Poll GetViewFinderData in a loop
        var consecutiveErrors = 0
        let maxErrors = 15

        while !Task.isCancelled && isLiveViewActive {
            do {
                let data = try await sendPTPCommand(
                    opCode: CanonPTP.CanonOpCode.getViewFinderData.rawValue,
                    params: [0x00200000]
                )

                consecutiveErrors = 0

                if let jpegData = data.findJPEGData(),
                   let image = UIImage(data: jpegData) {
                    liveViewImage = image
                }

                // ~30fps target
                try await Task.sleep(nanoseconds: 33_000_000)

            } catch {
                if Task.isCancelled || !isLiveViewActive { break }

                consecutiveErrors += 1
                if consecutiveErrors >= maxErrors {
                    logger.error("Live view stopped after \(maxErrors) consecutive errors")
                    isLiveViewActive = false
                    break
                }

                logger.warning("Live view frame error (\(consecutiveErrors)/\(maxErrors)): \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        isLiveViewActive = false
        liveViewTask = nil
        logger.info("Live view loop ended")
    }

    // MARK: - Photo Capture

    /// Capture a photo: trigger shutter, wait for image, download it.
    func capturePhoto() async throws -> CapturedPhoto {
        guard connectionState.isReady, cameraDevice != nil else {
            throw PhotoBoothError.cameraNotConnected
        }

        isCapturing = true
        defer { isCapturing = false }

        // Pause live view during capture
        let wasLiveViewActive = isLiveViewActive
        if wasLiveViewActive {
            stopLiveView()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        logger.info("Starting capture sequence…")

        let photo: CapturedPhoto
        do {
            photo = try await captureViaRemoteRelease()
        } catch {
            logger.warning("RemoteRelease failed, trying InitiateCapture: \(error.localizedDescription)")
            photo = try await captureViaInitiateCapture()
        }

        lastCapturedPhoto = photo
        logger.info("Photo captured: \(photo.imageData.count) bytes, \(photo.width)×\(photo.height)")

        // Resume live view
        if wasLiveViewActive {
            try? await Task.sleep(nanoseconds: 500_000_000)
            startLiveView()
        }

        return photo
    }

    /// Canon-specific capture via RemoteReleaseOn/Off.
    private func captureViaRemoteRelease() async throws -> CapturedPhoto {
        // Half-press for autofocus
        _ = try await sendPTPCommand(
            opCode: CanonPTP.CanonOpCode.remoteReleaseOn.rawValue,
            params: [CanonPTP.ReleaseParam.focus.rawValue, 0x00]
        )
        try await Task.sleep(nanoseconds: 300_000_000) // AF lock

        // Full press — shutter fires
        _ = try await sendPTPCommand(
            opCode: CanonPTP.CanonOpCode.remoteReleaseOn.rawValue,
            params: [CanonPTP.ReleaseParam.release.rawValue, 0x00]
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        // Release shutter
        _ = try await sendPTPCommand(
            opCode: CanonPTP.CanonOpCode.remoteReleaseOff.rawValue,
            params: [0x03]
        )

        // Poll events for ObjectAdded, then download
        return try await waitForCaptureAndDownload()
    }

    /// Standard PTP fallback capture.
    private func captureViaInitiateCapture() async throws -> CapturedPhoto {
        _ = try await sendPTPCommand(
            opCode: CanonPTP.OpCode.initiateCapture.rawValue,
            params: [0x00000000, 0x00000000]
        )
        try await Task.sleep(nanoseconds: 1_500_000_000) // wait for image
        return try await downloadLatestImage()
    }

    /// Poll GetEvent for ObjectAdded (0xC101) event, then download the new object.
    private func waitForCaptureAndDownload() async throws -> CapturedPhoto {
        let maxPolls = 30

        for poll in 0..<maxPolls {
            try await Task.sleep(nanoseconds: 200_000_000)

            if let eventData = try? await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.getEvent.rawValue
            ) {
                if let handle = parseObjectAddedEvent(from: eventData) {
                    logger.info("ObjectAdded event: handle 0x\(String(handle, radix: 16))")
                    return try await downloadObject(handle: handle)
                }
            }

            logger.debug("GetEvent poll \(poll + 1)/\(maxPolls) — no ObjectAdded yet")
        }

        // Fallback: no event received, try downloading the latest file
        logger.warning("No ObjectAdded event — falling back to latest handle")
        return try await downloadLatestImage()
    }

    /// Parse Canon event data for ObjectAdded (0xC101).
    /// Canon event format: [UInt32 length][UInt32 eventCode][UInt32 params...]
    private func parseObjectAddedEvent(from data: Data) -> UInt32? {
        guard data.count >= 12 else { return nil }

        var offset = 0
        while offset + 8 <= data.count {
            let recordLen = Int(data.readUInt32(at: offset))
            guard recordLen >= 8, offset + recordLen <= data.count else { break }

            let eventCode = data.readUInt32(at: offset + 4)
            if eventCode == 0xC101 && recordLen >= 12 {
                let handle = data.readUInt32(at: offset + 8)
                if handle != 0 { return handle }
            }

            offset += recordLen
        }
        return nil
    }

    // MARK: - Image Download

    /// Download a specific object by handle.
    private func downloadObject(handle: UInt32) async throws -> CapturedPhoto {
        logger.info("Downloading object 0x\(String(handle, radix: 16))…")

        let imageData = try await sendPTPCommand(
            opCode: CanonPTP.OpCode.getObject.rawValue,
            params: [handle]
        )

        if let jpegData = imageData.findJPEGData() {
            let image = UIImage(data: jpegData)
            return CapturedPhoto(
                imageData: jpegData,
                timestamp: .now,
                width: Int(image?.size.width ?? 0),
                height: Int(image?.size.height ?? 0)
            )
        }

        // Response might BE the JPEG directly
        guard imageData.count > 1000, UIImage(data: imageData) != nil else {
            throw PhotoBoothError.imageDownloadFailed
        }
        let image = UIImage(data: imageData)
        return CapturedPhoto(
            imageData: imageData,
            timestamp: .now,
            width: Int(image?.size.width ?? 0),
            height: Int(image?.size.height ?? 0)
        )
    }

    /// Download the most recently added image by scanning object handles.
    private func downloadLatestImage() async throws -> CapturedPhoto {
        let handlesData = try await sendPTPCommand(
            opCode: CanonPTP.OpCode.getObjectHandles.rawValue,
            params: [0xFFFFFFFF, 0x00000000, 0x00000000]
        )

        let handle = try extractLastHandle(from: handlesData)
        return try await downloadObject(handle: handle)
    }

    /// Extract the last (most recent) object handle from a PTP GetObjectHandles response.
    private func extractLastHandle(from data: Data) throws -> UInt32 {
        // Try without PTP header first (offset 0), then with header (offset 12)
        for startOffset in [0, 12] {
            guard data.count > startOffset + 4 else { continue }
            let count = data.readUInt32(at: startOffset)
            guard count > 0, count < 100_000 else { continue } // sanity check
            let lastIdx = startOffset + 4 + (Int(count) - 1) * 4
            guard data.count >= lastIdx + 4 else { continue }
            let handle = data.readUInt32(at: lastIdx)
            if handle != 0 { return handle }
        }
        throw PhotoBoothError.noImagesFound
    }
}

// MARK: - ICDeviceBrowserDelegate

extension CameraManager: ICDeviceBrowserDelegate {

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        let deviceName = device.name ?? "Unknown"

        Task { @MainActor in
            logger.info("Device found: \(deviceName), type: \(device.type.rawValue)")

            guard let camera = device as? ICCameraDevice else {
                logger.info("Skipping non-camera device")
                return
            }

            logger.info("Canon camera found: \(deviceName)")

            cameraDevice = camera
            camera.delegate = self
            deviceInfo.name = deviceName
            connectionState = .found(deviceName)

            camera.requestOpenSession()
            connectionState = .openingSession
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        let deviceName = device.name ?? "Unknown"

        Task { @MainActor in
            logger.info("Device removed: \(deviceName)")

            stopLiveView()
            cameraDevice?.delegate = nil
            cameraDevice = nil
            transactionID = 0
            connectionState = .disconnected
            deviceInfo = CameraDeviceInfo()
            liveViewImage = nil
        }
    }
}

// MARK: - ICCameraDeviceDelegate

extension CameraManager: ICCameraDeviceDelegate {

    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        let deviceName = device.name ?? "Unknown"

        Task { @MainActor in
            if let error {
                logger.error("Session open failed: \(error.localizedDescription)")
                connectionState = .error(error.localizedDescription)
                return
            }

            logger.info("PTP session opened for: \(deviceName)")
            // On iOS, PTP commands can only be sent after deviceDidBecomeReady(withCompleteContentCatalog:)
            // So we just log here and wait for that callback to send GetDeviceInfo
        }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        Task { @MainActor in
            logger.info("PTP session closed")
            connectionState = .disconnected
            deviceInfo.isConnected = false
        }
    }

    nonisolated func deviceDidBecomeReady(_ device: ICDevice) {
        logger.info("Camera ready: \(device.name ?? "Unknown")")
    }

    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in
            logger.info("Camera physically removed")
            stopLiveView()
            cameraDevice?.delegate = nil
            cameraDevice = nil
            transactionID = 0
            connectionState = .disconnected
            deviceInfo = CameraDeviceInfo()
            liveViewImage = nil
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        logger.debug("Camera added \(items.count) items")
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        logger.debug("Camera removed \(items.count) items")
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: (any Error)?) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
        logger.debug("PTP event: \(eventData.hexPrefix(32))")
    }

    nonisolated func device(_ device: ICDevice, didReceiveStatusInformation status: [ICDeviceStatus: Any]) {
        logger.debug("Status update received")
    }

    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        logger.info("Camera ready with complete catalog — now safe to send PTP commands")
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.readDeviceInfo()

            // Enable remote mode, then auto-start live view
            await self.enableRemoteMode()
            self.startLiveView()
        }
    }

    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}

    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, shouldGetThumbnailOf item: ICCameraItem) -> Bool { false }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, shouldGetMetadataOf item: ICCameraItem) -> Bool { false }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didCompleteDeleteFilesWithError error: (any Error)?) {}

    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
}
