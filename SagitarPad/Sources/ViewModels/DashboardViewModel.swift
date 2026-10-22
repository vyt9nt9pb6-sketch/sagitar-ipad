import SwiftUI
import UIKit
import SagitarCore

/// 儀表板的狀態：目前的資料來源、最新快照與連線狀態。
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: TelemetrySnapshot = .empty
    @Published private(set) var connection: ConnectionState = .disconnected
    @Published private(set) var sourceKind: DataSourceKind = .simulator

    private var source: VehicleDataSource?
    private var subscriptions: [Task<Void, Never>] = []
    private var fuelParameters = FuelParameters()
    private var pollInterval: TimeInterval = 0.1
    private var bleScanAll = true

    func apply(settings: AppSettings) {
        fuelParameters = settings.fuelParameters
        pollInterval = settings.pollInterval
        bleScanAll = settings.bleScanAll
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
    }

    /// 切換資料來源（會中斷目前的連線）。
    func select(_ kind: DataSourceKind) {
        stop()
        sourceKind = kind
        snapshot = .empty
        let newSource = makeSource(kind)
        source = newSource
        subscriptions = [
            Task { [weak self] in
                for await s in newSource.telemetryStream() {
                    self?.snapshot = s
                }
            },
            Task { [weak self] in
                for await c in newSource.connectionStateStream() {
                    self?.connection = c
                }
            },
        ]
        newSource.start()
    }

    func reconnect() { select(sourceKind) }

    func resetTrip() { source?.resetTrip() }

    func stop() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        source?.stop()
        source = nil
        connection = .disconnected
    }

    private func makeSource(_ kind: DataSourceKind) -> VehicleDataSource {
        switch kind {
        case .simulator:
            return SimulatedDataSource(parameters: fuelParameters)
        case .bleOBD:
            let config = ELM327DataSource.Configuration(pollInterval: pollInterval, fuel: fuelParameters)
            let options = BLEOBDTransport.Options(scanAllDevices: bleScanAll)
            return ELM327BLEDataSource.make(configuration: config, options: options)
        case .exlap:
            return ExlapDataSource()
        }
    }
}
