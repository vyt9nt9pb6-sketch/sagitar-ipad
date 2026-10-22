import Foundation

/// 模擬資料來源：沒有車也能展示整個儀表板。
public final class SimulatedDataSource: VehicleDataSource, @unchecked Sendable {
    public let kind: DataSourceKind = .simulator
    private let telemetry = AsyncBroadcaster<TelemetrySnapshot>(initial: .empty)
    private let state = AsyncBroadcaster<ConnectionState>(initial: .disconnected)
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var simulator: DrivingSimulator
    private var trip = TripComputer()
    private let updateInterval: TimeInterval
    /// 模擬時間倍率（測試可加速）
    private let timeScale: Double

    public init(seed: UInt64 = 2018, updateInterval: TimeInterval = 0.2, timeScale: Double = 1, parameters: FuelParameters = .init()) {
        self.simulator = DrivingSimulator(seed: seed, parameters: parameters)
        self.updateInterval = updateInterval
        self.timeScale = timeScale
    }

    public func telemetryStream() -> AsyncStream<TelemetrySnapshot> { telemetry.stream() }
    public func connectionStateStream() -> AsyncStream<ConnectionState> { state.stream() }

    public func start() {
        lock.lock()
        guard task == nil else { lock.unlock(); return }
        task = Task { [weak self] in await self?.run() }
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        task?.cancel()
        task = nil
        lock.unlock()
        state.send(.disconnected)
    }

    public func resetTrip() {
        lock.lock()
        trip.reset()
        lock.unlock()
    }

    /// 前進一步並產生快照（測試可直接呼叫，不需等待計時器）。
    public func tick(dt: TimeInterval, now: Date) -> TelemetrySnapshot {
        lock.lock()
        defer { lock.unlock() }
        simulator.step(dt: dt)
        let s = simulator
        let lph = FuelCalculator.litersPerHour(mafGramsPerSecond: s.mafGramsPerSecond, parameters: s.parameters)
        trip.update(speedKmh: s.speedKmh, fuelLitersPerHour: lph, engineRunning: s.rpm > 0, at: now)
        return TelemetrySnapshot(
            timestamp: now,
            speedKmh: s.speedKmh.rounded(),
            rpm: s.rpm,
            coolantTempC: s.coolantTempC.rounded(),
            controlModuleVoltage: (s.voltage * 100).rounded() / 100,
            mafGramsPerSecond: s.mafGramsPerSecond,
            fuelLevelPercent: s.fuelLevelPercent,
            instantFuelLitersPerHour: lph,
            instantFuelLitersPer100km: FuelCalculator.litersPer100km(litersPerHour: lph, speedKmh: s.speedKmh, parameters: s.parameters),
            trip: trip.summary
        )
    }

    private func run() async {
        state.send(.connecting(deviceName: "Simulator"))
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        state.send(.connected(detail: "Simulator · ISO 15765-4 CAN (11/500)"))
        var simulatedNow = Date()
        while !Task.isCancelled {
            simulatedNow = simulatedNow.addingTimeInterval(updateInterval * timeScale)
            telemetry.send(tick(dt: updateInterval * timeScale, now: simulatedNow))
            try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
        }
    }
}
