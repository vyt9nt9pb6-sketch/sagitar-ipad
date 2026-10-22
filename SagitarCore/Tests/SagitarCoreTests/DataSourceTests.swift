import XCTest
@testable import SagitarCore

final class DataSourceTests: XCTestCase {

    private func config() -> ELM327DataSource.Configuration {
        .init(pollInterval: 0.01, slowPollEvery: 2, retryDelay: 0.05, maxFailuresBeforeSkip: 2,
              timeouts: .init(command: 0.3, reset: 0.5, protocolSearch: 0.5))
    }

    /// 等到串流中出現符合條件的值
    private func first<T: Sendable>(_ stream: AsyncStream<T>, timeout: TimeInterval = 3,
                                    where predicate: @escaping @Sendable (T) -> Bool) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                for await v in stream where predicate(v) { return v }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let r = await group.next() ?? nil
            group.cancelAll()
            return r
        }
    }

    func testELM327DataSourceProducesSnapshot() async throws {
        let emu = ELM327Emulator()
        let transportBox = TransportBox()
        let source = ELM327DataSource(configuration: config()) {
            let t = emu.makeTransport(chunkSize: 20)
            transportBox.set(t)
            return t
        }
        source.start()
        let connected = await first(source.connectionStateStream()) { $0.isConnected }
        XCTAssertNotNil(connected)
        if case .connected(let detail)? = connected {
            XCTAssertTrue(detail.contains("ELM327"), detail)
        }
        let snap = await first(source.telemetryStream()) { $0.coolantTempC != nil && $0.rpm != nil }
        source.stop()
        let s = try XCTUnwrap(snap)
        XCTAssertEqual(s.rpm, 1726)
        XCTAssertEqual(s.speedKmh, 60)
        XCTAssertEqual(s.coolantTempC, 83)
        XCTAssertEqual(s.controlModuleVoltage!, 14.19, accuracy: 0.001)
        XCTAssertEqual(s.fuelLevelPercent!, 50.196, accuracy: 0.01)
        XCTAssertEqual(s.mafGramsPerSecond, 10)
        XCTAssertEqual(s.instantFuelLitersPer100km!, 5.4787, accuracy: 0.001)

        // 送出的每一條指令都必須在白名單內
        let sent = try XCTUnwrap(transportBox.get()).sentCommands
        XCTAssertFalse(sent.isEmpty)
        for cmd in sent { XCTAssertTrue(OBDCommandWhitelist.isAllowed(cmd), cmd) }
    }

    func testFallbacksWhenMAFAndVoltagePIDsUnsupported() async throws {
        let emu = ELM327Emulator()
        emu.set {
            $0.values[0x10] = nil
            $0.values[0x42] = nil
            $0.bitmasks[0x00] = [0x98, 0x3A, 0x80, 0x13] // 沒有 0x10
            $0.bitmasks[0x40] = [0x00, 0x00, 0x00, 0x00] // 沒有 0x42
            $0.voltageText = "13.9V"
        }
        let source = ELM327DataSource(configuration: config()) { emu.makeTransport() }
        source.start()
        let snap = await first(source.telemetryStream()) { $0.mafGramsPerSecond != nil && $0.controlModuleVoltage != nil }
        source.stop()
        let s = try XCTUnwrap(snap)
        // MAP 80 kPa、IAT 25 °C、1726 rpm → 速度—密度法估計
        let expected = FuelCalculator.estimatedMAF(rpm: 1726, mapKPa: 80, intakeAirTempC: 25)
        XCTAssertEqual(s.mafGramsPerSecond!, expected, accuracy: 0.001)
        XCTAssertEqual(s.controlModuleVoltage!, 13.9, accuracy: 0.001) // ATRV
    }

    func testVehicleNotRespondingState() async throws {
        let emu = ELM327Emulator()
        emu.set { $0.vehicleConnected = false }
        let source = ELM327DataSource(configuration: config()) { emu.makeTransport() }
        source.start()
        let state = await first(source.connectionStateStream()) {
            if case .vehicleNotResponding = $0 { return true }
            return false
        }
        XCTAssertNotNil(state)
        // 之後「發動」→ 應自動連上
        emu.set { $0.vehicleConnected = true }
        let connected = await first(source.connectionStateStream()) { $0.isConnected }
        source.stop()
        XCTAssertNotNil(connected)
    }

    func testConnectFailureReportsFailedState() async throws {
        let source = ELM327DataSource(configuration: config()) {
            let t = MockOBDTransport { _ in nil }
            t.failConnect = true
            return t
        }
        source.start()
        let state = await first(source.connectionStateStream()) {
            if case .failed = $0 { return true }
            return false
        }
        source.stop()
        XCTAssertNotNil(state)
    }

    // MARK: 模擬器

    func testDrivingSimulatorIsDeterministicAndRealistic() {
        var a = DrivingSimulator(seed: 42)
        var b = DrivingSimulator(seed: 42)
        var maxSpeed = 0.0, maxRPM = 0.0, minRPM = Double.infinity
        var sawStop = false, sawMoving = false
        for _ in 0..<(30 * 60 * 5) { // 30 分鐘、5 Hz
            a.step(dt: 0.2); b.step(dt: 0.2)
            XCTAssertEqual(a.speedKmh, b.speedKmh)
            maxSpeed = max(maxSpeed, a.speedKmh)
            maxRPM = max(maxRPM, a.rpm)
            minRPM = min(minRPM, a.rpm)
            if a.speedKmh == 0 { sawStop = true } else { sawMoving = true }
            XCTAssertGreaterThanOrEqual(a.speedKmh, 0)
            XCTAssertLessThanOrEqual(a.speedKmh, 125)
            XCTAssertGreaterThan(a.mafGramsPerSecond, 0)
            XCTAssertTrue((13.6...14.6).contains(a.voltage))
        }
        XCTAssertTrue(sawStop && sawMoving)
        XCTAssertGreaterThan(maxSpeed, 50)
        XCTAssertLessThan(maxRPM, 6300)
        XCTAssertGreaterThan(minRPM, 700)
        XCTAssertGreaterThan(a.coolantTempC, 85) // 30 分鐘後已暖車
        XCTAssertLessThan(a.fuelLevelPercent, 68)
    }

    func testSimulatedTripAverageConsumptionPlausible() {
        let source = SimulatedDataSource(seed: 7)
        var now = Date(timeIntervalSince1970: 0)
        var last = TelemetrySnapshot.empty
        for _ in 0..<(20 * 60 * 5) {
            now = now.addingTimeInterval(0.2)
            last = source.tick(dt: 0.2, now: now)
        }
        let trip = last.trip
        XCTAssertGreaterThan(trip.distanceKm, 5)
        XCTAssertEqual(trip.elapsedSeconds, 20 * 60 - 0.2, accuracy: 0.5)
        let avg = try? XCTUnwrap(trip.averageLitersPer100km)
        XCTAssertNotNil(avg)
        XCTAssertTrue((3...15).contains(avg ?? 0), "avg L/100km = \(avg ?? -1)")
        source.resetTrip()
        let after = source.tick(dt: 0.2, now: now.addingTimeInterval(0.2))
        XCTAssertLessThan(after.trip.distanceKm, 0.01)
    }

    func testSimulatedDataSourceStreams() async {
        let source = SimulatedDataSource(updateInterval: 0.02)
        source.start()
        let connected = await first(source.connectionStateStream()) { $0.isConnected }
        XCTAssertNotNil(connected)
        let snap = await first(source.telemetryStream()) { $0.rpm != nil }
        XCTAssertNotNil(snap)
        source.stop()
    }

    func testExlapStubReportsUnavailable() async {
        let source = ExlapDataSource()
        source.start()
        let state = await first(source.connectionStateStream()) {
            if case .unavailable = $0 { return true }
            return false
        }
        XCTAssertNotNil(state)
    }
}

final class TransportBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: MockOBDTransport?
    func set(_ t: MockOBDTransport) { lock.lock(); value = t; lock.unlock() }
    func get() -> MockOBDTransport? { lock.lock(); defer { lock.unlock() }; return value }
}
