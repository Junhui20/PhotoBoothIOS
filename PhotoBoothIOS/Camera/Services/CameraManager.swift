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
    @Published var cameraSettings = CameraSettings()

    // MARK: - Private

    private nonisolated let logger = Logger(subsystem: "com.instamedia.photoboothios", category: "CameraManager")
    private var deviceBrowser: ICDeviceBrowser?
    private var cameraDevice: ICCameraDevice?
    private var transactionID: UInt32 = 0
    private var liveViewTask: Task<Void, Never>?

    /// Files added by the camera (set via `cameraDevice(_:didAdd:)` delegate).
    /// Cleared before each capture, populated when camera writes a new image.
    private var pendingCaptureFiles: [ICCameraFile] = []

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
        cameraSettings = CameraSettings()
        liveViewImage = nil
        lastCapturedPhoto = nil
    }

    // MARK: - PTP Transaction ID

    private func nextTransactionID() -> UInt32 {
        transactionID += 1
        return transactionID
    }

    // MARK: - PTP Command Sending

    /// Send a PTP command and return the data-phase payload.
    ///
    /// Apple's `requestSendPTPCommand` completion gives two Data params:
    ///   - 1st (`responseData`): the DATA-phase payload (JPEG, events, object data, device info…)
    ///   - 2nd (`ptpResponseData`): the 12-byte PTP RESPONSE container (status code + txID)
    ///
    /// We return the data payload to callers and check the status container for errors.
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
                    self?.logger.error("PTP framework error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }

                // responseData    = DATA-phase payload (what callers need)
                // ptpResponseData = RESPONSE container  (12-byte status header)
                self?.logger.debug("PTP RX payload=\(responseData.count)B status=\(ptpResponseData.count)B")
                if !responseData.isEmpty {
                    self?.logger.debug("  payload head: \(responseData.hexPrefix(64))")
                }

                // Check PTP response code from the status container
                if ptpResponseData.count >= 8 {
                    let respCode = ptpResponseData.readUInt16(at: 6)
                    self?.logger.debug("  PTP status: 0x\(String(respCode, radix: 16))")

                    if respCode != 0x2001 && respCode != 0x0000 {
                        let hex = String(respCode, radix: 16)
                        self?.logger.warning("PTP command 0x\(String(opCode, radix: 16)) failed: 0x\(hex)")
                        continuation.resume(
                            throwing: PhotoBoothError.ptpCommandFailed("0x\(hex)")
                        )
                        return
                    }
                }

                // Return the data-phase payload (may be empty for void commands)
                continuation.resume(returning: responseData)
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

        // Step 3: Drain pending events and parse initial camera settings
        if let eventData = try? await sendPTPCommand(
            opCode: CanonPTP.CanonOpCode.getEvent.rawValue
        ), !eventData.isEmpty {
            parsePropertyChangedEvents(from: eventData)
            logger.info("Initial camera settings parsed from \(eventData.count)-byte event data")
        }
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

        // Restore EVF output to camera LCD (Canon EOS method — no TerminateViewfinder needed)
        if cameraDevice != nil {
            Task {
                let evfData = CanonPTP.buildPropertyChangeData(
                    propCode: CanonPTP.DeviceProp.evfOutputDevice.rawValue,
                    value: CanonPTP.EVFOutputDevice.tft.rawValue
                )
                _ = try? await sendPTPCommand(
                    opCode: CanonPTP.CanonOpCode.setDevicePropEx.rawValue,
                    outData: evfData
                )
                logger.info("EVF output restored to camera LCD — live view stopped")
            }
        }
    }

    /// Internal live view polling loop.
    ///
    /// Canon EOS live view sequence (per libgphoto2):
    ///   1. SetDevicePropValueEx(EVF_OutputDevice = PC)  ← redirect viewfinder to USB
    ///   2. GetEvent (drain property-change events)
    ///   3. Poll GetViewFinderData (0x9153) in a loop
    ///   4. To stop: SetDevicePropValueEx(EVF_OutputDevice = TFT)
    ///
    /// NOTE: InitViewfinder (0x9151) / TerminateViewfinder (0x9152) are PowerShot
    /// commands and are NOT used for Canon EOS cameras.
    private func liveViewLoop() async {
        // Step 1: Set EVF output device to USB
        // Canon EOS cameras default to TFT (camera LCD). Must set to 0x02 (PC/USB)
        // before GetViewFinderData returns frames.
        var evfSet = false
        do {
            let evfData = CanonPTP.buildPropertyChangeData(
                propCode: CanonPTP.DeviceProp.evfOutputDevice.rawValue,
                value: CanonPTP.EVFOutputDevice.pc.rawValue
            )
            _ = try await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.setDevicePropEx.rawValue,
                outData: evfData
            )
            logger.info("EVF_OutputDevice set to PC (0x02) — viewfinder output redirected to USB ✓")
            evfSet = true
        } catch {
            logger.warning("EVF_OutputDevice=PC failed: \(error.localizedDescription)")
            // Fallback: try TFT+PC (0x03) — some cameras prefer both enabled
            do {
                let evfData = CanonPTP.buildPropertyChangeData(
                    propCode: CanonPTP.DeviceProp.evfOutputDevice.rawValue,
                    value: CanonPTP.EVFOutputDevice.both.rawValue
                )
                _ = try await sendPTPCommand(
                    opCode: CanonPTP.CanonOpCode.setDevicePropEx.rawValue,
                    outData: evfData
                )
                logger.info("EVF_OutputDevice set to TFT+PC (0x03) — fallback ✓")
                evfSet = true
            } catch {
                logger.error("EVF_OutputDevice fallback also failed: \(error.localizedDescription)")
            }
        }

        if !evfSet {
            logger.error("Cannot redirect viewfinder to USB — live view will not work")
            isLiveViewActive = false
            liveViewTask = nil
            return
        }

        // Step 2: Drain events generated by EVF property change
        // The camera generates property-change events that must be consumed
        // before GetViewFinderData will return clean frames.
        _ = try? await sendPTPCommand(
            opCode: CanonPTP.CanonOpCode.getEvent.rawValue
        )
        logger.debug("Events drained after EVF property change")

        // Brief delay for camera to prepare viewfinder output pipeline
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Step 3: Poll GetViewFinderData in a loop
        var consecutiveErrors = 0
        var framesReceived = 0
        let maxErrors = 50  // Generous tolerance — camera warm-up can take several seconds

        while !Task.isCancelled && isLiveViewActive {
            do {
                let data = try await sendPTPCommand(
                    opCode: CanonPTP.CanonOpCode.getViewFinderData.rawValue,
                    params: [0x00100000]  // 1MB buffer size hint (per libgphoto2)
                )

                consecutiveErrors = 0

                if data.isEmpty {
                    logger.debug("GetViewFinderData returned empty payload")
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    continue
                }

                if let jpegData = data.findJPEGData(),
                   let image = UIImage(data: jpegData) {
                    liveViewImage = image
                    framesReceived += 1
                    if framesReceived <= 5 || framesReceived % 100 == 0 {
                        logger.info("Live view frame #\(framesReceived): \(jpegData.count) bytes, \(Int(image.size.width))×\(Int(image.size.height))")
                    }
                } else {
                    logger.debug("No JPEG found in \(data.count)-byte payload: \(data.hexPrefix(64))")
                }

                // Periodically poll events for settings changes (~every 3s)
                if framesReceived % 90 == 0 {
                    if let eventData = try? await sendPTPCommand(
                        opCode: CanonPTP.CanonOpCode.getEvent.rawValue
                    ), !eventData.isEmpty {
                        parsePropertyChangedEvents(from: eventData)
                    }
                }

                // ~30fps target
                try await Task.sleep(nanoseconds: 33_000_000)

            } catch {
                if Task.isCancelled || !isLiveViewActive { break }

                consecutiveErrors += 1

                // Drain events periodically — camera may fire events that block frames
                if consecutiveErrors % 5 == 0 {
                    _ = try? await sendPTPCommand(
                        opCode: CanonPTP.CanonOpCode.getEvent.rawValue
                    )
                }

                if consecutiveErrors >= maxErrors {
                    logger.error("Live view stopped after \(maxErrors) consecutive errors")
                    isLiveViewActive = false
                    break
                }

                if consecutiveErrors <= 10 {
                    logger.info("Live view frame error (\(consecutiveErrors)/\(maxErrors)): \(error.localizedDescription)")
                } else {
                    logger.debug("Live view frame error (\(consecutiveErrors)/\(maxErrors)): \(error.localizedDescription)")
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        isLiveViewActive = false
        liveViewTask = nil
        logger.info("Live view loop ended after \(framesReceived) frames")
    }

    // MARK: - Camera Settings

    /// Parse Canon EOS events from GetEvent (0x9116) data.
    ///
    /// Each event record: `[UInt32 size][UInt32 eventCode][data...]`
    ///   - 0xC189 = PropertyChanged: `[size=16][code][propCode][value]`
    ///   - 0xC18A = AvailListChanged: `[size][code][propCode][count][values...]`
    private func parsePropertyChangedEvents(from data: Data) {
        guard data.count >= 16 else { return }

        var offset = 0
        var propsFound = 0
        var listsFound = 0

        while offset + 8 <= data.count {
            let recordLen = Int(data.readUInt32(at: offset))
            guard recordLen >= 8 else {
                offset += 4
                continue
            }
            guard offset + recordLen <= data.count else { break }

            let eventCode = data.readUInt32(at: offset + 4)

            if eventCode == 0xC189 && recordLen >= 16 {
                // PropertyChanged — current value for a property
                let propCode = data.readUInt32(at: offset + 8)
                let value = data.readUInt32(at: offset + 12)
                applyPropertyValue(propCode: propCode, value: value)
                propsFound += 1
            } else if eventCode == 0xC18A && recordLen >= 16 {
                // AvailListChanged — list of valid values for a property
                let propCode = data.readUInt32(at: offset + 8)
                let count = Int(data.readUInt32(at: offset + 12))
                var values: [UInt32] = []
                for i in 0..<count {
                    let valOffset = offset + 16 + i * 4
                    guard valOffset + 4 <= offset + recordLen else { break }
                    values.append(data.readUInt32(at: valOffset))
                }
                applyAvailableValues(propCode: propCode, values: values)
                listsFound += 1
            }

            offset += recordLen
        }

        if propsFound > 0 || listsFound > 0 {
            logger.debug("Events parsed: \(propsFound) values, \(listsFound) available-lists")
        }
    }

    /// Apply a single Canon EOS property value to the current settings.
    private func applyPropertyValue(propCode: UInt32, value: UInt32) {
        switch propCode {
        case CanonPTP.DeviceProp.iso.rawValue:
            cameraSettings.iso = ISOValue(rawValue: value) ?? .unknown
        case CanonPTP.DeviceProp.aperture.rawValue:
            cameraSettings.aperture = ApertureValue(rawValue: value) ?? .unknown
        case CanonPTP.DeviceProp.shutterSpeed.rawValue:
            cameraSettings.shutterSpeed = ShutterSpeedValue(rawValue: value) ?? .unknown
        case CanonPTP.DeviceProp.whiteBalance.rawValue:
            cameraSettings.whiteBalance = WhiteBalanceValue(rawValue: value) ?? .unknown
        case CanonPTP.DeviceProp.exposureComp.rawValue:
            cameraSettings.exposureComp = ExposureCompValue(rawValue: value) ?? .zero
        case CanonPTP.DeviceProp.batteryLevel.rawValue:
            cameraSettings.batteryLevel = Int(value)
        case CanonPTP.DeviceProp.availableShots.rawValue:
            cameraSettings.availableShots = Int(value)
        default:
            break
        }
    }

    /// Apply available-values list from a Canon EOS 0xC18A event.
    /// These lists tell us which values the camera/lens/mode currently supports.
    private func applyAvailableValues(propCode: UInt32, values: [UInt32]) {
        switch propCode {
        case CanonPTP.DeviceProp.iso.rawValue:
            cameraSettings.availableISOs = values.compactMap { ISOValue(rawValue: $0) }
                .filter { $0 != .unknown }
            logger.info("Available ISOs: \(self.cameraSettings.availableISOs.map(\.displayName))")
        case CanonPTP.DeviceProp.aperture.rawValue:
            cameraSettings.availableApertures = values.compactMap { ApertureValue(rawValue: $0) }
                .filter { $0 != .unknown }
            logger.info("Available apertures: \(self.cameraSettings.availableApertures.map(\.displayName))")
        case CanonPTP.DeviceProp.shutterSpeed.rawValue:
            cameraSettings.availableShutterSpeeds = values.compactMap { ShutterSpeedValue(rawValue: $0) }
                .filter { $0 != .unknown }
            logger.info("Available shutter speeds: \(self.cameraSettings.availableShutterSpeeds.map(\.displayName))")
        case CanonPTP.DeviceProp.exposureComp.rawValue:
            cameraSettings.availableExposureComps = values.compactMap { ExposureCompValue(rawValue: $0) }
            logger.info("Available EV comp: \(self.cameraSettings.availableExposureComps.map(\.displayName))")
        default:
            break
        }
    }

    /// Set a camera property via Canon SetDevicePropValueEx (0x9110).
    /// After setting, drains events to get the confirmed value back.
    func setCameraProperty(_ prop: CanonPTP.DeviceProp, value: UInt32) async throws {
        let propData = CanonPTP.buildPropertyChangeData(
            propCode: prop.rawValue,
            value: value
        )
        _ = try await sendPTPCommand(
            opCode: CanonPTP.CanonOpCode.setDevicePropEx.rawValue,
            outData: propData
        )
        logger.info("Set property 0x\(String(prop.rawValue, radix: 16)) = 0x\(String(value, radix: 16))")

        // Drain events to get the confirmed value back from camera
        if let eventData = try? await sendPTPCommand(
            opCode: CanonPTP.CanonOpCode.getEvent.rawValue
        ), !eventData.isEmpty {
            parsePropertyChangedEvents(from: eventData)
        }
    }

    /// Set ISO value on the camera.
    func setISO(_ iso: ISOValue) async throws {
        try await setCameraProperty(.iso, value: iso.rawValue)
    }

    /// Set aperture value on the camera.
    func setAperture(_ av: ApertureValue) async throws {
        try await setCameraProperty(.aperture, value: av.rawValue)
    }

    /// Set shutter speed on the camera.
    func setShutterSpeed(_ tv: ShutterSpeedValue) async throws {
        try await setCameraProperty(.shutterSpeed, value: tv.rawValue)
    }

    /// Set white balance mode on the camera.
    func setWhiteBalance(_ wb: WhiteBalanceValue) async throws {
        try await setCameraProperty(.whiteBalance, value: wb.rawValue)
    }

    /// Set exposure compensation on the camera.
    func setExposureComp(_ ev: ExposureCompValue) async throws {
        try await setCameraProperty(.exposureComp, value: ev.rawValue)
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

        // Clear pending files so we detect only NEW files from this capture
        pendingCaptureFiles.removeAll()

        logger.info("Starting capture sequence…")

        // Step 1: Fire the shutter
        let shutterFired = await triggerShutter()

        let photo: CapturedPhoto
        if shutterFired {
            // Step 2: Download the captured image (multiple strategies)
            photo = try await downloadCapturedImage()
        } else {
            // Shutter commands all failed — try standard PTP InitiateCapture as last resort
            logger.warning("All shutter commands failed, trying InitiateCapture…")
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

    // MARK: - Shutter Trigger

    /// Fire the shutter via Canon RemoteReleaseOn. Returns true if shutter triggered.
    private func triggerShutter() async -> Bool {
        // Strategy 1: Immediate capture (focus + release combined, param=3)
        do {
            _ = try await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.remoteReleaseOn.rawValue,
                params: [CanonPTP.ReleaseParam.immediate.rawValue, 0x00]
            )
            logger.info("RemoteReleaseOn(immediate) — shutter fired ✓")

            try? await Task.sleep(nanoseconds: 300_000_000)
            _ = try? await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.remoteReleaseOff.rawValue,
                params: [0x03]
            )
            return true
        } catch {
            logger.info("Immediate capture failed (0x\(String(format: "%04X", CanonPTP.ReleaseParam.immediate.rawValue))), trying focus + release…")
        }

        // Strategy 2: Separate half-press (AF) then full-press (release)
        do {
            _ = try await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.remoteReleaseOn.rawValue,
                params: [CanonPTP.ReleaseParam.focus.rawValue, 0x00]
            )
            logger.info("RemoteReleaseOn(focus) — AF started ✓")
        } catch {
            logger.error("RemoteReleaseOn(focus) failed: \(error.localizedDescription)")
            return false
        }

        // Wait for AF to lock (was 300ms → Busy; now 800ms)
        try? await Task.sleep(nanoseconds: 800_000_000)

        // Full press with retry on DeviceBusy (0x2019)
        for attempt in 1...5 {
            do {
                _ = try await sendPTPCommand(
                    opCode: CanonPTP.CanonOpCode.remoteReleaseOn.rawValue,
                    params: [CanonPTP.ReleaseParam.release.rawValue, 0x00]
                )
                logger.info("RemoteReleaseOn(release) succeeded on attempt \(attempt) ✓")
                break
            } catch {
                logger.warning("Release attempt \(attempt)/5: \(error.localizedDescription)")
                if attempt < 5 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        _ = try? await sendPTPCommand(
            opCode: CanonPTP.CanonOpCode.remoteReleaseOff.rawValue,
            params: [0x03]
        )

        return true // AF half-press likely triggered capture even if full-press was busy
    }

    // MARK: - Image Download (Multi-Strategy)

    /// Download the just-captured image using multiple fallback strategies.
    private func downloadCapturedImage() async throws -> CapturedPhoto {
        // Strategy 1: Wait for ICCameraDevice didAdd delegate (ImageCaptureCore file system)
        // This is the most reliable — Apple handles PTP transfer internally
        logger.info("Waiting for captured file via ImageCaptureCore…")
        for poll in 1...50 { // up to 10 seconds (50 × 200ms)
            if let file = pendingCaptureFiles.last {
                logger.info("File detected via IC delegate: \(file.name ?? "?") (\(file.fileSize) bytes)")
                return try await downloadViaICFramework(file: file)
            }
            if poll % 10 == 0 {
                logger.debug("IC file poll \(poll)/50 — waiting for didAdd…")
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        logger.warning("No file via IC delegate after 10s")

        // Strategy 2: Poll GetEvent for ObjectAdded (PTP-level events)
        logger.info("Trying PTP GetEvent polling…")
        for poll in 1...15 {
            if let eventData = try? await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.getEvent.rawValue
            ), !eventData.isEmpty {
                if let handle = parseObjectAddedEvent(from: eventData) {
                    logger.info("ObjectAdded event: handle 0x\(String(handle, radix: 16))")
                    return try await downloadObject(handle: handle)
                }
            }
            logger.debug("GetEvent poll \(poll)/15 — no ObjectAdded")
            try await Task.sleep(nanoseconds: 300_000_000)
        }

        // Strategy 3: Get latest object handle (brute force)
        logger.warning("No events — trying GetObjectHandles for latest file…")
        return try await downloadLatestImage()
    }

    /// Download a file using Apple's ImageCaptureCore framework (not raw PTP).
    /// Uses `ICCameraFile.requestReadData` which handles PTP transfer internally.
    private func downloadViaICFramework(file: ICCameraFile) async throws -> CapturedPhoto {
        logger.info("Downloading via IC framework: \(file.name ?? "?"), size=\(file.fileSize)")

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            file.requestReadData(atOffset: 0, length: file.fileSize) { readData, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let readData, !readData.isEmpty {
                    continuation.resume(returning: readData)
                } else {
                    continuation.resume(throwing: PhotoBoothError.imageDownloadFailed)
                }
            }
        }

        logger.info("IC download complete: \(data.count) bytes")

        // Extract JPEG if wrapped in container, or use directly
        let imageData = data.findJPEGData() ?? data
        guard let image = UIImage(data: imageData) else {
            throw PhotoBoothError.imageDownloadFailed
        }

        return CapturedPhoto(
            imageData: imageData,
            timestamp: .now,
            width: Int(image.size.width),
            height: Int(image.size.height)
        )
    }

    /// Standard PTP fallback capture (only used when Canon remote commands all fail).
    private func captureViaInitiateCapture() async throws -> CapturedPhoto {
        _ = try await sendPTPCommand(
            opCode: CanonPTP.OpCode.initiateCapture.rawValue,
            params: [0x00000000, 0x00000000]
        )
        try await Task.sleep(nanoseconds: 1_500_000_000)
        return try await downloadLatestImage()
    }

    /// Poll GetEvent for ObjectAdded (0xC101) event, then download the new object.
    private func waitForCaptureAndDownload() async throws -> CapturedPhoto {
        let maxPolls = 30

        for poll in 0..<maxPolls {
            try await Task.sleep(nanoseconds: 200_000_000)

            if let eventData = try? await sendPTPCommand(
                opCode: CanonPTP.CanonOpCode.getEvent.rawValue
            ), !eventData.isEmpty {
                if let handle = parseObjectAddedEvent(from: eventData) {
                    logger.info("ObjectAdded event: handle 0x\(String(handle, radix: 16))")
                    return try await downloadObject(handle: handle)
                }
            }

            logger.debug("GetEvent poll \(poll + 1)/\(maxPolls) — no ObjectAdded yet")
        }

        logger.warning("No ObjectAdded event — falling back to latest handle")
        return try await downloadLatestImage()
    }

    /// Parse Canon EOS event data for object-related events.
    /// Canon event format: [UInt32 recordSize][UInt32 eventCode][UInt32 params...]
    /// Event codes checked:
    ///   0xC101 = RequestObjectTransfer (older cameras)
    ///   0xC181 = ObjectAddedEx (newer cameras, DSLR)
    ///   0xC1A7 = ObjectContentChanged (EOS R-series mirrorless, contains handle)
    private func parseObjectAddedEvent(from data: Data) -> UInt32? {
        guard data.count >= 8 else { return nil }

        logger.debug("Parsing events from \(data.count) bytes: \(data.hexPrefix(128))")

        var offset = 0
        while offset + 8 <= data.count {
            let recordLen = Int(data.readUInt32(at: offset))
            guard recordLen >= 8 else {
                // Skip malformed record
                offset += 4
                continue
            }
            guard offset + recordLen <= data.count else { break }

            let eventCode = data.readUInt32(at: offset + 4)
            logger.debug("  Event record: size=\(recordLen) code=0x\(String(eventCode, radix: 16))")

            // Check all known object-added event variants
            let isObjectEvent = (eventCode == 0xC101 || eventCode == 0xC181 || eventCode == 0xC1A7)
            if isObjectEvent && recordLen >= 12 {
                let handle = data.readUInt32(at: offset + 8)
                if handle != 0 {
                    logger.info("  → Object event 0x\(String(eventCode, radix: 16)) handle=0x\(String(handle, radix: 16))")
                    return handle
                }
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
            cameraSettings = CameraSettings()
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
            cameraSettings = CameraSettings()
            liveViewImage = nil
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for item in items {
                if let file = item as? ICCameraFile {
                    self.logger.info("📸 New file on camera: \(file.name ?? "unnamed"), size=\(file.fileSize)")
                    self.pendingCaptureFiles.append(file)
                } else {
                    self.logger.debug("Camera added non-file item: \(item.name ?? "?")")
                }
            }
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        logger.debug("Camera removed \(items.count) items")
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: (any Error)?) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
        // PTP events arrive via the interrupt endpoint (separate from GetEvent polling)
        logger.info("PTP interrupt event [\(eventData.count) bytes]: \(eventData.hexPrefix(64))")
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
