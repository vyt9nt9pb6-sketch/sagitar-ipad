import SwiftUI
import SagitarCore

/// 使用者設定（存在 UserDefaults）。
@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("dataSource") var dataSourceRaw: String = DataSourceKind.simulator.rawValue
    /// 油耗校正係數（實際加油量 ÷ App 推估量）
    @AppStorage("fuelCalibration") var fuelCalibration: Double = 1.0
    /// 引擎排氣量 L
    @AppStorage("engineDisplacement") var engineDisplacement: Double = 1.4
    /// 油箱容量 L
    @AppStorage("tankCapacity") var tankCapacity: Double = 55
    /// 常用電話號碼
    @AppStorage("favoritePhone") var favoritePhone: String = ""
    /// 保持螢幕常亮
    @AppStorage("keepScreenOn") var keepScreenOn: Bool = true
    /// BLE：掃描所有裝置並以名稱過濾（有些轉接器不廣播服務 UUID）
    @AppStorage("bleScanAll") var bleScanAll: Bool = true
    /// 輪詢間隔（秒）
    @AppStorage("pollInterval") var pollInterval: Double = 0.1

    var dataSource: DataSourceKind {
        get { DataSourceKind(rawValue: dataSourceRaw) ?? .simulator }
        set { dataSourceRaw = newValue.rawValue; objectWillChange.send() }
    }

    var fuelParameters: FuelParameters {
        FuelParameters(calibrationFactor: fuelCalibration,
                       engineDisplacementLiters: engineDisplacement,
                       tankCapacityLiters: tankCapacity)
    }
}
