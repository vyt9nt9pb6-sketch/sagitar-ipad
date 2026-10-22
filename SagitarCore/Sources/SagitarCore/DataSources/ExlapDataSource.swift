import Foundation

/// Exlap 資料來源（**預留位置，尚未實作**）。
///
/// 背景：這台 2018 Sagitar 的 MIB2 Standard 主機（MIB2-C-V11-20170609）回報
/// Exlap v2.27 / CarIf v2.29。Exlap（Extended Link Access Protocol）是 VW 給手機 App
/// （例如 App-Connect / 「Car-Net」類 App）透過主機讀取車輛資料的介面，
/// 可提供標準 OBD-II 拿不到的 VW 專屬資料（車門 / 後車廂狀態、外部溫度、剩餘里程、
/// 原廠行車電腦、檔位、方向盤角度等，實際能拿到哪些要看主機授權與車型編碼）。
///
/// 要真正實作，需要（皆**未經本專案驗證**，依公開的逆向工程資料整理）：
/// 1. 傳輸：主機與 iPad 之間的 IP 連線（主機的 Wi-Fi 熱點，或 USB 網路），以及
///    Exlap 伺服器的主機位址 / 連接埠。MIB2 Standard 是否開放 Wi-Fi 與 Exlap 給第三方，
///    需要實車確認（很多 Standard 主機沒有 Wi-Fi）。
/// 2. 協定：XML 訊息（`<Req>`、`<Rsp>`、`<Dat>` 等），以 `Subscribe` 訂閱資料點、
///    `Interface` 列出可用的 URL / 資料點。
/// 3. 認證：連線後需要挑戰—回應（challenge/response，雜湊 nonce + App 帳號 / 金鑰）。
///    金鑰原本只發給 VW 授權的 App，取得方式可能涉及授權條款，請自行評估。
/// 4. 主機端可能需要用 VCDS / OBDeleven 開啟 App-Connect 相關編碼；
///    **修改主機編碼有風險，本 App 不做任何寫入**。
///
/// 目前實作只會回報 `.unavailable`，讓 UI 的資料來源選單有這個選項。
public final class ExlapDataSource: VehicleDataSource, @unchecked Sendable {
    public let kind: DataSourceKind = .exlap
    private let telemetry = AsyncBroadcaster<TelemetrySnapshot>(initial: .empty)
    private let state = AsyncBroadcaster<ConnectionState>(initial: .disconnected)

    /// 未來會需要的連線設定（佔位）
    public struct Configuration: Sendable {
        public var host: String
        public var port: UInt16
        public var appName: String
        public init(host: String = "", port: UInt16 = 0, appName: String = "SagitarPad") {
            self.host = host
            self.port = port
            self.appName = appName
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func telemetryStream() -> AsyncStream<TelemetrySnapshot> { telemetry.stream() }
    public func connectionStateStream() -> AsyncStream<ConnectionState> { state.stream() }

    public func start() {
        state.send(.unavailable(reason: "Exlap not implemented"))
    }

    public func stop() {
        state.send(.disconnected)
    }

    public func resetTrip() {}
}
