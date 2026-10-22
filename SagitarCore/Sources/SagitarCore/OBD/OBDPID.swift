import Foundation

/// 本 App 使用的標準 OBD-II Mode 01 PID（SAE J1979）。只讀取，不寫入。
public enum OBDPID: UInt8, CaseIterable, Sendable {
    /// 支援的 PID 01–20 位元遮罩
    case supported01to20 = 0x00
    /// 冷卻液溫度：A − 40 °C
    case coolantTemperature = 0x05
    /// 進氣歧管絕對壓力 MAP：A kPa（MAF 不支援時用來推估進氣量）
    case intakeManifoldPressure = 0x0B
    /// 引擎轉速：(256A + B) / 4 rpm
    case engineRPM = 0x0C
    /// 車速：A km/h
    case vehicleSpeed = 0x0D
    /// 進氣溫度 IAT：A − 40 °C（MAF 不支援時用來推估進氣量）
    case intakeAirTemperature = 0x0F
    /// 進氣流量 MAF：(256A + B) / 100 g/s
    case mafAirFlow = 0x10
    /// 支援的 PID 21–40 位元遮罩
    case supported21to40 = 0x20
    /// 油箱油量：100A / 255 %
    case fuelTankLevel = 0x2F
    /// 支援的 PID 41–60 位元遮罩
    case supported41to60 = 0x40
    /// 控制模組電壓：(256A + B) / 1000 V
    case controlModuleVoltage = 0x42

    /// Mode 01 指令字串，例如 "010C"
    public var command: String { String(format: "01%02X", rawValue) }

    /// 回應中應有的資料位元組數（不含 0x41 與 PID）
    public var dataByteCount: Int {
        switch self {
        case .supported01to20, .supported21to40, .supported41to60: return 4
        case .engineRPM, .mafAirFlow, .controlModuleVoltage: return 2
        case .coolantTemperature, .vehicleSpeed, .fuelTankLevel, .intakeManifoldPressure, .intakeAirTemperature: return 1
        }
    }

    public var isSupportBitmask: Bool {
        switch self {
        case .supported01to20, .supported21to40, .supported41to60: return true
        default: return false
        }
    }

    /// 依 SAE J1979 公式把資料位元組轉成工程單位；位元組不足時回傳 nil。
    public func decode(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= dataByteCount else { return nil }
        let a = Double(bytes[0])
        let b = bytes.count > 1 ? Double(bytes[1]) : 0
        switch self {
        case .coolantTemperature: return OBDFormulas.coolantTemperature(a: bytes[0])
        case .engineRPM: return OBDFormulas.rpm(a: bytes[0], b: bytes[1])
        case .vehicleSpeed: return a
        case .intakeManifoldPressure: return a
        case .intakeAirTemperature: return a - 40
        case .mafAirFlow: return OBDFormulas.maf(a: bytes[0], b: bytes[1])
        case .fuelTankLevel: return OBDFormulas.fuelLevel(a: bytes[0])
        case .controlModuleVoltage: return OBDFormulas.controlModuleVoltage(a: bytes[0], b: bytes[1])
        case .supported01to20, .supported21to40, .supported41to60:
            _ = b
            return nil // 位元遮罩請用 OBDFormulas.supportedPIDs
        }
    }
}

/// OBD-II 公式（純函式，方便測試）。
public enum OBDFormulas {
    public static func rpm(a: UInt8, b: UInt8) -> Double { (256 * Double(a) + Double(b)) / 4 }
    public static func speed(a: UInt8) -> Double { Double(a) }
    public static func coolantTemperature(a: UInt8) -> Double { Double(a) - 40 }
    public static func controlModuleVoltage(a: UInt8, b: UInt8) -> Double { (256 * Double(a) + Double(b)) / 1000 }
    public static func fuelLevel(a: UInt8) -> Double { 100 * Double(a) / 255 }
    public static func maf(a: UInt8, b: UInt8) -> Double { (256 * Double(a) + Double(b)) / 100 }

    /// 解析「支援的 PID」位元遮罩。`base` 為查詢的 PID（0x00、0x20、0x40…），
    /// 最高位元代表 base+1。
    public static func supportedPIDs(base: UInt8, bitmask bytes: [UInt8]) -> Set<UInt8> {
        guard bytes.count >= 4 else { return [] }
        var result = Set<UInt8>()
        for (byteIndex, byte) in bytes.prefix(4).enumerated() {
            for bit in 0..<8 where byte & (0x80 >> UInt8(bit)) != 0 {
                result.insert(base &+ UInt8(byteIndex * 8 + bit + 1))
            }
        }
        return result
    }
}
