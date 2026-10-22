import Foundation

/// 車輛資料來源。UI 只依賴這個協定，不管資料來自模擬器、BLE OBD 或未來的 Exlap。
public protocol VehicleDataSource: AnyObject, Sendable {
    var kind: DataSourceKind { get }
    /// 遙測快照串流（每個呼叫者各自一條串流；新訂閱者會先收到最新值）
    func telemetryStream() -> AsyncStream<TelemetrySnapshot>
    /// 連線狀態串流
    func connectionStateStream() -> AsyncStream<ConnectionState>
    /// 開始（連線、輪詢）
    func start()
    /// 停止並中斷連線
    func stop()
    /// 重設行車電腦
    func resetTrip()
}
