import Foundation

/// Canon-specific PTP operation codes, command builder, and response parsers.
enum CanonPTP {

    // MARK: - Standard PTP Operation Codes

    enum OpCode: UInt16 {
        case getDeviceInfo       = 0x1001
        case openSession         = 0x1002
        case closeSession        = 0x1003
        case getStorageIDs       = 0x1004
        case getNumObjects       = 0x1006
        case getObjectHandles    = 0x1007
        case getObjectInfo       = 0x1008
        case getObject           = 0x1009
        case getThumb            = 0x100A
        case initiateCapture     = 0x100E
        case getDevicePropDesc   = 0x1014
        case getDevicePropValue  = 0x1015
        case setDevicePropValue  = 0x1016
        case getPartialObject    = 0x101B
    }

    // MARK: - Canon EOS Vendor-Specific Operation Codes
    // Reference: libgphoto2/camlibs/ptp2/ptp.h (canonical Canon PTP source)
    // CRITICAL FIX: Previous codes had 0x9128=getLiveViewImage which is actually
    // RemoteReleaseOn. Calling "live view" would have fired the shutter.

    enum CanonOpCode: UInt16 {
        case getDeviceInfoEx      = 0x9108
        case remoteRelease        = 0x910F  // Simple shutter trigger
        case setDevicePropEx      = 0x9110
        case getRemoteMode        = 0x9113  // Was incorrectly: remoteReleaseOn
        case setRemoteMode        = 0x9114  // Was incorrectly: remoteReleaseOff
        case setEventMode         = 0x9115  // Enable event notifications
        case getEvent             = 0x9116  // Was incorrectly: 0x9126
        case remoteReleaseOn      = 0x9128  // Half/full press shutter
        case remoteReleaseOff     = 0x9129  // Release shutter
        case getLiveViewProps      = 0x912B
        case setLiveViewProps      = 0x912C
        case initViewfinder       = 0x9151  // Start live view output
        case terminateViewfinder  = 0x9152  // Stop live view output
        case getViewFinderData    = 0x9153  // Get one live view JPEG frame
        case moveFocus            = 0x9155  // Move focus lens
        case setRemoteShootMode   = 0x9160  // Newer mirrorless remote mode
    }

    // MARK: - Remote Release Parameters (for RemoteReleaseOn 0x9128)

    enum ReleaseParam: UInt32 {
        case focus     = 0x01  // Half-press (autofocus)
        case release   = 0x02  // Full press (shutter)
        case immediate = 0x03  // Focus + release combined
    }

    // MARK: - Canon Device Properties

    enum DeviceProp: UInt32 {
        case aperture            = 0xD101
        case shutterSpeed        = 0xD102
        case iso                 = 0xD103
        case exposureComp        = 0xD104
        case autoExposureMode    = 0xD105
        case driveMode           = 0xD106
        case meteringMode        = 0xD107
        case focusMode           = 0xD108
        case whiteBalance        = 0xD109
        case colorTemperature    = 0xD10A
        case imageQuality        = 0xD10C
        case imageFormat         = 0xD10D
        case lensName            = 0xD115
        case batteryLevel        = 0xD11C
        case availableShots      = 0xD120
    }

    // MARK: - PTP Response Codes

    enum ResponseCode: UInt16 {
        case ok                      = 0x2001
        case generalError            = 0x2002
        case sessionNotOpen          = 0x2003
        case invalidTransID          = 0x2004
        case operationNotSupported   = 0x2005
        case parameterNotSupported   = 0x2006
        case incompleteTransfer      = 0x2007
        case invalidStorageID        = 0x2008
        case invalidObjectHandle     = 0x2009
        case deviceBusy              = 0x2019
        case sessionAlreadyOpen      = 0x201E

        var isSuccess: Bool { self == .ok }
    }

    // MARK: - PTP Command Builder

    /// Build a PTP command data block (little-endian).
    /// Structure: [UInt32 length] [UInt16 type=1] [UInt16 opCode] [UInt32 transactionID] [UInt32 params...]
    static func buildCommand(opCode: UInt16, transactionID: UInt32, params: [UInt32] = []) -> Data {
        let headerSize: UInt32 = 12
        let totalSize = headerSize + UInt32(params.count * 4)

        var data = Data(capacity: Int(totalSize))
        data.appendUInt32(totalSize)
        data.appendUInt16(0x0001)           // PTP container type: Command
        data.appendUInt16(opCode)
        data.appendUInt32(transactionID)

        for param in params {
            data.appendUInt32(param)
        }
        return data
    }

    /// Build command from standard op code.
    static func buildCommand(opCode: OpCode, transactionID: UInt32, params: [UInt32] = []) -> Data {
        buildCommand(opCode: opCode.rawValue, transactionID: transactionID, params: params)
    }

    /// Build command from Canon vendor op code.
    static func buildCommand(canonOpCode: CanonOpCode, transactionID: UInt32, params: [UInt32] = []) -> Data {
        buildCommand(opCode: canonOpCode.rawValue, transactionID: transactionID, params: params)
    }

    // MARK: - Response Parsing

    /// Parse response code from PTP response data.
    /// PTP response container: [UInt32 length][UInt16 type=3][UInt16 responseCode][UInt32 transactionID]
    static func parseResponseCode(from data: Data) -> ResponseCode? {
        guard data.count >= 8 else { return nil }
        let code = data.readUInt16(at: 6)
        return ResponseCode(rawValue: code)
    }

    // MARK: - DeviceInfo Parser

    /// Parsed camera identity from PTP GetDeviceInfo (0x1001) response.
    struct DeviceInfo {
        var standardVersion: UInt16 = 0
        var vendorExtensionID: UInt32 = 0
        var manufacturer: String = ""
        var model: String = ""
        var deviceVersion: String = ""
        var serialNumber: String = ""
    }

    /// Parse the PTP DeviceInfo dataset.
    ///
    /// The dataset layout (after any PTP response header):
    /// ```
    /// UInt16  StandardVersion
    /// UInt32  VendorExtensionID
    /// UInt16  VendorExtensionVersion
    /// String  VendorExtensionDesc
    /// UInt16  FunctionalMode
    /// UInt32Array  OperationsSupported
    /// UInt32Array  EventsSupported
    /// UInt32Array  DevicePropertiesSupported
    /// UInt32Array  CaptureFormats
    /// UInt32Array  ImageFormats
    /// String  Manufacturer
    /// String  Model
    /// String  DeviceVersion
    /// String  SerialNumber
    /// ```
    static func parseDeviceInfo(from data: Data) -> DeviceInfo? {
        guard data.count >= 12 else { return nil }

        var info = DeviceInfo()
        var offset = 0

        // StandardVersion (UInt16)
        info.standardVersion = data.readUInt16(at: offset)
        offset += 2

        // VendorExtensionID (UInt32)
        info.vendorExtensionID = data.readUInt32(at: offset)
        offset += 4

        // VendorExtensionVersion (UInt16)
        offset += 2

        // VendorExtensionDesc (PTP String)
        let (_, extDescBytes) = data.readPTPString(at: offset)
        offset += extDescBytes

        // FunctionalMode (UInt16)
        offset += 2

        // OperationsSupported (UInt32 array)
        let opsBytes = data.ptpArrayByteCount(at: offset)
        guard opsBytes > 0 else { return info }
        offset += opsBytes

        // EventsSupported (UInt32 array)
        let eventsBytes = data.ptpArrayByteCount(at: offset)
        guard eventsBytes > 0 else { return info }
        offset += eventsBytes

        // DevicePropertiesSupported (UInt32 array)
        let propsBytes = data.ptpArrayByteCount(at: offset)
        guard propsBytes > 0 else { return info }
        offset += propsBytes

        // CaptureFormats (UInt32 array)
        let capFmtBytes = data.ptpArrayByteCount(at: offset)
        guard capFmtBytes > 0 else { return info }
        offset += capFmtBytes

        // ImageFormats (UInt32 array)
        let imgFmtBytes = data.ptpArrayByteCount(at: offset)
        guard imgFmtBytes > 0 else { return info }
        offset += imgFmtBytes

        // Manufacturer (PTP String)
        let (manufacturer, mfgBytes) = data.readPTPString(at: offset)
        info.manufacturer = manufacturer
        offset += mfgBytes

        // Model (PTP String)
        let (model, modelBytes) = data.readPTPString(at: offset)
        info.model = model
        offset += modelBytes

        // DeviceVersion / Firmware (PTP String)
        let (deviceVersion, dvBytes) = data.readPTPString(at: offset)
        info.deviceVersion = deviceVersion
        offset += dvBytes

        // SerialNumber (PTP String)
        let (serial, _) = data.readPTPString(at: offset)
        info.serialNumber = serial

        return info
    }
}
