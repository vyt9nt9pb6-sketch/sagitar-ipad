import Foundation

/// ELM327 / OBD 層的錯誤。
public enum ELM327Error: Error, Equatable, Sendable {
    /// "NO DATA"：ECU 沒回應這個 PID（常見於不支援的 PID）
    case noData
    /// "UNABLE TO CONNECT"：找不到 OBD 協定（多半是未開 ACC / 未發動）
    case unableToConnect
    /// "?"：轉接器不認得指令
    case unknownCommand
    /// "STOPPED"：指令被中斷（通常是送出太快）
    case stopped
    /// "BUS INIT: ...ERROR"、"BUS ERROR"、"CAN ERROR"、"BUS BUSY" 等匯流排錯誤
    case busError(String)
    /// "BUFFER FULL"
    case bufferFull
    /// 其他轉接器錯誤字串（例如 "ERROR"、"DATA ERROR"、"<RX ERROR"）
    case adapterError(String)
    /// 回應中找不到預期的資料
    case malformedResponse(String)
    /// 指令不在唯讀白名單內，拒絕送出
    case commandNotAllowed(String)
    /// 等待 '>' 提示字元逾時
    case timeout(command: String)
    /// 尚未連線 / 傳輸層已關閉
    case notConnected
    /// 已有指令在等待回應
    case busy
    /// 傳輸層錯誤
    case transport(String)
}
