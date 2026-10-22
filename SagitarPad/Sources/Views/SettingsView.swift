import SwiftUI
import SagitarCore

/// 設定：資料來源、油耗參數、電話、螢幕、關於 / 安全提醒。
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.section.source") {
                    Picker("source.title", selection: Binding(
                        get: { settings.dataSource },
                        set: { settings.dataSource = $0; model.select($0) })) {
                        ForEach(DataSourceKind.allCases) { kind in
                            Text(LocalizedStringKey("source.\(kind.rawValue)")).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(LocalizedStringKey("source.\(settings.dataSource.rawValue).help"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("settings.bleScanAll", isOn: $settings.bleScanAll)
                    Stepper(value: $settings.pollInterval, in: 0...1, step: 0.05) {
                        Text("settings.pollInterval \(settings.pollInterval.formatted(.number.precision(.fractionLength(2))))")
                    }
                }

                Section {
                    Stepper(value: $settings.fuelCalibration, in: 0.5...1.5, step: 0.01) {
                        Text("settings.calibration \(settings.fuelCalibration.formatted(.number.precision(.fractionLength(2))))")
                    }
                    Picker("settings.displacement", selection: $settings.engineDisplacement) {
                        Text(verbatim: "1.2T").tag(1.2)
                        Text(verbatim: "1.4T").tag(1.4)
                        Text(verbatim: "1.5").tag(1.5)
                        Text(verbatim: "1.6").tag(1.6)
                    }
                    Stepper(value: $settings.tankCapacity, in: 30...80, step: 1) {
                        Text("settings.tank \(Int(settings.tankCapacity))")
                    }
                } header: {
                    Text("settings.section.fuel")
                } footer: {
                    Text("settings.fuel.footer")
                }

                Section("settings.section.phone") {
                    TextField("settings.favoritePhone", text: $settings.favoritePhone)
                        .keyboardType(.phonePad)
                }

                Section("settings.section.display") {
                    Toggle("settings.keepScreenOn", isOn: $settings.keepScreenOn)
                }

                Section("settings.section.about") {
                    Text("about.vehicle")
                    Text("about.readOnly")
                    Text("about.safety")
                        .foregroundStyle(Theme.warning)
                }
            }
            .navigationTitle(Text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        model.apply(settings: settings)
                        model.reconnect()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
