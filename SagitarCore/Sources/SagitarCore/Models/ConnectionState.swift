import Foundation

/// 資料來源的連線狀態。
public enum ConnectionState: Sendable, Equatable {
    case disconnected
    /// 藍牙不可用（關閉、未授權、不支援）
    case unavailable(reason: String)
    case scanning
    case connecting(deviceName: String)
    /// 已連到轉接器，正在送初始化指令 / 搜尋 OBD 協定
    case initializing(step: String)
    /// 已連線；`detail` 例如 "ELM327 v1.5 · ISO 15765-4 CAN"
    case connected(detail: String)
    /// 轉接器在線，但 ECU 沒回應（例如未發動 / 未開 ACC）
    case vehicleNotResponding(reason: String)
    case failed(reason: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// 簡短的英文代碼，方便 UI 對應在地化字串。
    public var code: String {
        switch self {
        case .disconnected: return "disconnected"
        case .unavailable: return "unavailable"
        case .scanning: return "scanning"
        case .connecting: return "connecting"
        case .initializing: return "initializing"
        case .connected: return "connected"
        case .vehicleNotResponding: return "vehicleNotResponding"
        case .failed: return "failed"
        }
    }

    public var detail: String? {
        switch self {
        case .disconnected, .scanning: return nil
        case .unavailable(let r), .vehicleNotResponding(let r), .failed(let r): return r
        case .connecting(let n): return n
        case .initializing(let s): return s
        case .connected(let d): return d
        }
    }
}

/// 可選的資料來源種類。
public enum DataSourceKind: String, Sendable, CaseIterable, Identifiable, Codable {
    case simulator
    case bleOBD
    case exlap

    public var id: String { rawValue }
}
