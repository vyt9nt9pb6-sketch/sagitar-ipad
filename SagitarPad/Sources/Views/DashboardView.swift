import SwiftUI
import SagitarCore

/// 主畫面（橫向）：
/// ┌──────────────── 狀態列 ────────────────┐
/// │ 轉速錶+車速 │ 水溫 │ 電壓 │ 行車電腦      │
/// │            │ 瞬時油耗    │ （含油量）     │
/// ├──────────────── 捷徑列 ────────────────┤
struct DashboardView: View {
    @EnvironmentObject private var model: DashboardViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        let s = model.snapshot
        VStack(spacing: 0) {
            ConnectionStatusBar(
                state: model.connection,
                sourceKind: model.sourceKind,
                onSelectSource: { kind in
                    settings.dataSource = kind
                    model.select(kind)
                },
                onReconnect: { model.reconnect() },
                onSettings: { showSettings = true })

            HStack(spacing: 16) {
                // 左：轉速錶 + 車速
                RPMGaugeView(rpm: s.rpm, speedKmh: s.speedKmh)
                    .padding(8)
                    .card()
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)

                // 中：水溫、電壓、油耗
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        MetricCard(title: "card.coolant", systemImage: "thermometer.medium",
                                   value: Fmt.number(s.coolantTempC), unit: "unit.celsius",
                                   subtitle: coolantSubtitle(s.coolantTempC),
                                   tint: coolantTint(s.coolantTempC))
                        MetricCard(title: "card.voltage", systemImage: "minus.plus.batteryblock",
                                   value: Fmt.number(s.controlModuleVoltage, digits: 1), unit: "unit.volt",
                                   subtitle: voltageSubtitle(s.controlModuleVoltage, rpm: s.rpm),
                                   tint: voltageTint(s.controlModuleVoltage))
                    }
                    MetricCard(title: "card.instantFuel", systemImage: "drop.fill",
                               value: instantFuelValue(s), unit: instantFuelUnit(s),
                               subtitle: Text("card.instantFuel.avg \(Fmt.number(s.trip.averageLitersPer100km, digits: 1))"),
                               tint: Theme.accent,
                               progress: s.instantFuelLitersPer100km.map { min($0 / 20, 1) })
                }
                .frame(maxWidth: .infinity)

                // 右：行車電腦
                TripComputerCard(trip: s.trip, fuelLevelPercent: s.fuelLevelPercent,
                                 tankCapacity: settings.tankCapacity,
                                 onReset: { model.resetTrip() })
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            ShortcutBar()
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .padding(.top, 4)
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(model)
        }
    }

    // MARK: 顯示邏輯

    private func instantFuelValue(_ s: TelemetrySnapshot) -> String {
        if let per100 = s.instantFuelLitersPer100km { return Fmt.number(per100, digits: 1) }
        return Fmt.number(s.instantFuelLitersPerHour, digits: 1)
    }

    /// 車速低於門檻時改顯示 L/h（停車怠速時 L/100km 沒有意義）
    private func instantFuelUnit(_ s: TelemetrySnapshot) -> LocalizedStringKey {
        s.instantFuelLitersPer100km != nil ? "unit.l100km" : "unit.lph"
    }

    private func coolantTint(_ t: Double?) -> Color {
        guard let t else { return .white }
        if t < 60 { return Theme.accent }
        if t > 110 { return Theme.danger }
        if t > 103 { return Theme.warning }
        return .white
    }

    private func coolantSubtitle(_ t: Double?) -> Text? {
        guard let t else { return nil }
        if t < 60 { return Text("coolant.cold") }
        if t > 110 { return Text("coolant.hot") }
        return Text("coolant.normal")
    }

    private func voltageTint(_ v: Double?) -> Color {
        guard let v else { return .white }
        if v < 11.8 || v > 15.0 { return Theme.danger }
        if v < 12.4 { return Theme.warning }
        return .white
    }

    private func voltageSubtitle(_ v: Double?, rpm: Double?) -> Text? {
        guard let v else { return nil }
        let running = (rpm ?? 0) > 300
        if running { return v >= 13.2 ? Text("voltage.charging") : Text("voltage.lowCharge") }
        return v >= 12.4 ? Text("voltage.batteryOK") : Text("voltage.batteryLow")
    }
}
