import Foundation

// All methods are nonisolated — Data is a value type, safe to use from any context.
// The project default MainActor isolation must not apply to these pure helpers.
nonisolated extension Data {

    // MARK: - Safe Little-Endian Reads (byte-by-byte, no alignment issues)

    /// Read a little-endian UInt16 at the given byte offset.
    /// Uses byte-by-byte reconstruction to avoid alignment crashes on packed PTP data.
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        let base = startIndex.advanced(by: offset)
        return UInt16(self[base])
             | (UInt16(self[base.advanced(by: 1)]) << 8)
    }

    /// Read a little-endian UInt32 at the given byte offset.
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let base = startIndex.advanced(by: offset)
        return UInt32(self[base])
             | (UInt32(self[base.advanced(by: 1)]) << 8)
             | (UInt32(self[base.advanced(by: 2)]) << 16)
             | (UInt32(self[base.advanced(by: 3)]) << 24)
    }

    // MARK: - Little-Endian Writes

    /// Append a UInt16 in little-endian format.
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    /// Append a UInt32 in little-endian format.
    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    // MARK: - PTP String Parsing

    /// Read a PTP string at the given offset.
    /// PTP strings are: [UInt8 charCount] [UInt16 char1] [UInt16 char2] ... (UTF-16LE, null-terminated).
    /// Returns the parsed string and the total number of bytes consumed.
    func readPTPString(at offset: Int) -> (string: String, bytesConsumed: Int) {
        guard offset >= 0, offset < count else { return ("", 0) }

        let charCount = Int(self[startIndex.advanced(by: offset)])
        guard charCount > 0 else { return ("", 1) }

        let bytesNeeded = 1 + charCount * 2
        guard offset + bytesNeeded <= count else { return ("", 1) }

        var chars: [UInt16] = []
        chars.reserveCapacity(charCount)
        for i in 0..<charCount {
            let c = readUInt16(at: offset + 1 + i * 2)
            if c == 0 { break }
            chars.append(c)
        }
        return (String(utf16CodeUnits: chars, count: chars.count), bytesNeeded)
    }

    // MARK: - PTP Array Parsing

    /// Read a PTP UInt32 array: [UInt32 count] [UInt32 elem] ...
    /// Returns the total bytes consumed (4 + count * 4).
    func ptpArrayByteCount(at offset: Int) -> Int {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let arrayCount = Int(readUInt32(at: offset))
        return 4 + arrayCount * 4
    }

    // MARK: - PTP UInt16 Array Parsing

    /// Read a PTP UInt16 array: [UInt32 count] [UInt16 elem] ...
    /// Returns the total bytes consumed (4 + count * 2).
    func ptpUInt16ArrayByteCount(at offset: Int) -> Int {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let arrayCount = Int(readUInt32(at: offset))
        return 4 + arrayCount * 2
    }

    // MARK: - JPEG Extraction

    /// Find JPEG data within a PTP response buffer.
    /// Searches for SOI marker (0xFF 0xD8) and EOI marker (0xFF 0xD9).
    /// Canon GetViewFinderData (0x9153) embeds JPEG in a multi-segment response.
    func findJPEGData() -> Data? {
        guard count > 4 else { return nil }

        let bytes = [UInt8](self)
        for i in 0..<(bytes.count - 1) {
            guard bytes[i] == 0xFF, bytes[i + 1] == 0xD8 else { continue }

            // Found JPEG SOI — search backwards from end for EOI (0xFF 0xD9)
            for j in stride(from: bytes.count - 1, through: i + 3, by: -1) {
                if bytes[j] == 0xD9 && bytes[j - 1] == 0xFF {
                    return Data(bytes[i...j])
                }
            }
            // No EOI found — return from SOI to end (partial frame)
            return Data(bytes[i...])
        }
        return nil
    }

    // MARK: - Debug Helpers

    /// Hex string of the first N bytes, for PTP debug logging.
    func hexPrefix(_ maxBytes: Int = 64) -> String {
        prefix(maxBytes).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
