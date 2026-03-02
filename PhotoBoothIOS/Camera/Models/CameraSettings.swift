import Foundation

/// Current camera settings read from Canon EOS via PTP events.
///
/// Canon EOS cameras report property values through GetEvent (0x9116) data:
///   - 0xC189 = PropertyChanged: [size=16][code][propCode][value]
///   - 0xC18A = PropertyValuesAccepted: [size][code][propCode][count][values...]
/// Properties are set via SetDevicePropValueEx (0x9110).
struct CameraSettings {
    var iso: ISOValue = .unknown
    var aperture: ApertureValue = .unknown
    var shutterSpeed: ShutterSpeedValue = .unknown
    var whiteBalance: WhiteBalanceValue = .auto
    var exposureComp: ExposureCompValue = .zero
    var batteryLevel: Int = -1       // Canon EOS: 0=critical, 1=low, 2=half, 3=full. -1=unknown
    var availableShots: Int = -1

    // Available values reported by camera (from 0xC18A AvailListChanged events).
    // When non-empty, only these values can be set on the current camera/lens/mode.
    var availableISOs: [ISOValue] = []
    var availableApertures: [ApertureValue] = []
    var availableShutterSpeeds: [ShutterSpeedValue] = []
    var availableExposureComps: [ExposureCompValue] = []
}

// MARK: - ISO Values (Canon EOS hex encoding)

enum ISOValue: UInt32, CaseIterable, Identifiable {
    case auto    = 0x00000000
    case iso100  = 0x00000048
    case iso200  = 0x00000050
    case iso400  = 0x00000058
    case iso800  = 0x00000060
    case iso1600 = 0x00000068
    case iso3200 = 0x00000070
    case iso6400 = 0x00000078
    case iso12800 = 0x00000080
    case unknown = 0xFFFFFFFF

    var id: UInt32 { rawValue }

    var displayName: String {
        switch self {
        case .auto:     return "AUTO"
        case .iso100:   return "100"
        case .iso200:   return "200"
        case .iso400:   return "400"
        case .iso800:   return "800"
        case .iso1600:  return "1600"
        case .iso3200:  return "3200"
        case .iso6400:  return "6400"
        case .iso12800: return "12800"
        case .unknown:  return "—"
        }
    }

    /// User-selectable values (excludes .unknown)
    static var selectable: [ISOValue] {
        allCases.filter { $0 != .unknown }
    }
}

// MARK: - Aperture Values (Canon EOS APEX encoding)

enum ApertureValue: UInt32, CaseIterable, Identifiable {
    case f1_4  = 0x0D
    case f1_8  = 0x10
    case f2_0  = 0x13
    case f2_8  = 0x18
    case f3_5  = 0x1B
    case f4_0  = 0x20
    case f4_5  = 0x23
    case f5_0  = 0x25
    case f5_6  = 0x28
    case f6_3  = 0x2B
    case f7_1  = 0x2D
    case f8_0  = 0x30
    case f9_0  = 0x33
    case f10   = 0x35
    case f11   = 0x38
    case f13   = 0x3B
    case f14   = 0x3D
    case f16   = 0x40
    case f18   = 0x43
    case f20   = 0x45
    case f22   = 0x48
    case unknown = 0xFF

    var id: UInt32 { rawValue }

    var displayName: String {
        switch self {
        case .f1_4:  return "f/1.4"
        case .f1_8:  return "f/1.8"
        case .f2_0:  return "f/2"
        case .f2_8:  return "f/2.8"
        case .f3_5:  return "f/3.5"
        case .f4_0:  return "f/4"
        case .f4_5:  return "f/4.5"
        case .f5_0:  return "f/5"
        case .f5_6:  return "f/5.6"
        case .f6_3:  return "f/6.3"
        case .f7_1:  return "f/7.1"
        case .f8_0:  return "f/8"
        case .f9_0:  return "f/9"
        case .f10:   return "f/10"
        case .f11:   return "f/11"
        case .f13:   return "f/13"
        case .f14:   return "f/14"
        case .f16:   return "f/16"
        case .f18:   return "f/18"
        case .f20:   return "f/20"
        case .f22:   return "f/22"
        case .unknown: return "—"
        }
    }

    static var selectable: [ApertureValue] {
        allCases.filter { $0 != .unknown }
    }
}

// MARK: - Shutter Speed Values (Canon EOS APEX encoding)

enum ShutterSpeedValue: UInt32, CaseIterable, Identifiable {
    case s30     = 0x10
    case s15     = 0x13
    case s8      = 0x18
    case s4      = 0x1B
    case s2      = 0x1D
    case s1      = 0x20
    case s1_2    = 0x23
    case s1_4    = 0x25
    case s1_8    = 0x28
    case s1_15   = 0x2B
    case s1_30   = 0x2D
    case s1_60   = 0x30
    case s1_125  = 0x33
    case s1_250  = 0x35
    case s1_500  = 0x38
    case s1_1000 = 0x3B
    case s1_2000 = 0x3D
    case s1_4000 = 0x40
    case s1_8000 = 0x43
    case unknown = 0xFF

    var id: UInt32 { rawValue }

    var displayName: String {
        switch self {
        case .s30:     return "30\""
        case .s15:     return "15\""
        case .s8:      return "8\""
        case .s4:      return "4\""
        case .s2:      return "2\""
        case .s1:      return "1\""
        case .s1_2:    return "1/2"
        case .s1_4:    return "1/4"
        case .s1_8:    return "1/8"
        case .s1_15:   return "1/15"
        case .s1_30:   return "1/30"
        case .s1_60:   return "1/60"
        case .s1_125:  return "1/125"
        case .s1_250:  return "1/250"
        case .s1_500:  return "1/500"
        case .s1_1000: return "1/1000"
        case .s1_2000: return "1/2000"
        case .s1_4000: return "1/4000"
        case .s1_8000: return "1/8000"
        case .unknown: return "—"
        }
    }

    static var selectable: [ShutterSpeedValue] {
        allCases.filter { $0 != .unknown }
    }
}

// MARK: - White Balance Values

enum WhiteBalanceValue: UInt32, CaseIterable, Identifiable {
    case auto        = 0x00
    case daylight    = 0x01
    case shade       = 0x02
    case cloudy      = 0x03
    case tungsten    = 0x04
    case fluorescent = 0x05
    case flash       = 0x06
    case custom      = 0x08
    case colorTemp   = 0x09
    case unknown     = 0xFF

    var id: UInt32 { rawValue }

    var displayName: String {
        switch self {
        case .auto:        return "AWB"
        case .daylight:    return "Daylight"
        case .shade:       return "Shade"
        case .cloudy:      return "Cloudy"
        case .tungsten:    return "Tungsten"
        case .fluorescent: return "Fluorescent"
        case .flash:       return "Flash"
        case .custom:      return "Custom"
        case .colorTemp:   return "K"
        case .unknown:     return "—"
        }
    }

    var iconName: String {
        switch self {
        case .auto:        return "wand.and.stars"
        case .daylight:    return "sun.max"
        case .shade:       return "cloud.sun"
        case .cloudy:      return "cloud"
        case .tungsten:    return "lightbulb"
        case .fluorescent: return "light.tube.fluorescent"
        case .flash:       return "bolt"
        case .custom:      return "slider.horizontal.3"
        case .colorTemp:   return "thermometer"
        case .unknown:     return "questionmark"
        }
    }

    static var selectable: [WhiteBalanceValue] {
        allCases.filter { $0 != .unknown }
    }
}

// MARK: - Exposure Compensation Values (Canon EOS encoding)

enum ExposureCompValue: UInt32, CaseIterable, Identifiable {
    case minus3  = 0xE8
    case minus2_7 = 0xEB
    case minus2_3 = 0xED
    case minus2  = 0xF0
    case minus1_7 = 0xF3
    case minus1_3 = 0xF5
    case minus1  = 0xF8
    case minus0_7 = 0xFB
    case minus0_3 = 0xFD
    case zero    = 0x00
    case plus0_3 = 0x03
    case plus0_7 = 0x05
    case plus1   = 0x08
    case plus1_3 = 0x0B
    case plus1_7 = 0x0D
    case plus2   = 0x10
    case plus2_3 = 0x13
    case plus2_7 = 0x15
    case plus3   = 0x18

    var id: UInt32 { rawValue }

    var displayName: String {
        switch self {
        case .minus3:   return "-3"
        case .minus2_7: return "-2.7"
        case .minus2_3: return "-2.3"
        case .minus2:   return "-2"
        case .minus1_7: return "-1.7"
        case .minus1_3: return "-1.3"
        case .minus1:   return "-1"
        case .minus0_7: return "-0.7"
        case .minus0_3: return "-0.3"
        case .zero:     return "0"
        case .plus0_3:  return "+0.3"
        case .plus0_7:  return "+0.7"
        case .plus1:    return "+1"
        case .plus1_3:  return "+1.3"
        case .plus1_7:  return "+1.7"
        case .plus2:    return "+2"
        case .plus2_3:  return "+2.3"
        case .plus2_7:  return "+2.7"
        case .plus3:    return "+3"
        }
    }
}
