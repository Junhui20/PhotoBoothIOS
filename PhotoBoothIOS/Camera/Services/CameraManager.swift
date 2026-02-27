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

    // MARK: - Private

    private nonisolated let logger = Logger(subsystem: "com.instamedia.photoboothios", category: "CameraManager")
    private var deviceBrowser: ICDeviceBrowser?
    private var cameraDevice: ICCameraDevice?
    private var transactionID: UInt32 = 0

    // MARK: - Lifecycle

    override init() {
        super.init()
    }

    /// Start scanning for USB cameras.
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
        browser.start()
        deviceBrowser = browser

        logger.info("Device browser started")
    }

    /// Stop scanning and disconnect.
    func stopScanning() {
        deviceBrowser?.stop()
        deviceBrowser = nil
        cameraDevice?.requestCloseSession()
        cameraDevice?.delegate = nil
        cameraDevice = nil
        transactionID = 0
        connectionState = .disconnected
        deviceInfo = CameraDeviceInfo()
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
}

// MARK: - ICDeviceBrowserDelegate

extension CameraManager: @preconcurrency ICDeviceBrowserDelegate {

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        let deviceName = device.name ?? "Unknown"
        let deviceType = device.type

        Task { @MainActor in
            logger.info("Device found: \(deviceName), type: \(deviceType.rawValue)")

            guard deviceType == .camera, let camera = device as? ICCameraDevice else {
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

            cameraDevice?.delegate = nil
            cameraDevice = nil
            transactionID = 0
            connectionState = .disconnected
            deviceInfo = CameraDeviceInfo()
        }
    }
}

// MARK: - ICCameraDeviceDelegate

extension CameraManager: @preconcurrency ICCameraDeviceDelegate {

    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        let deviceName = device.name ?? "Unknown"

        Task { @MainActor in
            if let error {
                logger.error("Session open failed: \(error.localizedDescription)")
                connectionState = .error(error.localizedDescription)
                return
            }

            logger.info("PTP session opened for: \(deviceName)")
            await readDeviceInfo()
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
            cameraDevice?.delegate = nil
            cameraDevice = nil
            transactionID = 0
            connectionState = .disconnected
            deviceInfo = CameraDeviceInfo()
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
        logger.info("Camera ready with complete catalog")
    }

    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}

    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, shouldGetThumbnailOf item: ICCameraItem) -> Bool { false }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, shouldGetMetadataOf item: ICCameraItem) -> Bool { false }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didCompleteDeleteFilesWithError error: (any Error)?) {}

    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
}
