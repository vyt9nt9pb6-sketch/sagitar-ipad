import Foundation

/// 透過 ELM327 轉接器讀取標準 OBD-II PID 的資料來源。
/// 與傳輸層無關：iPad 上用 `BLEOBDTransport`（見 `ELM327BLEDataSource`），測試時用 `MockOBDTransport`。
public final class ELM327DataSource: VehicleDataSource, @unchecked Sendable {
    public struct Configuration: Sendable {
        /// 每輪輪詢之間的間隔（秒）
        public var pollInterval: TimeInterval
        /// 慢速 PID（水溫、電壓、油量）每幾輪讀一次
        public var slowPollEvery: Int
        /// 斷線 / ECU 無回應後多久重試
        public var retryDelay: TimeInterval
        /// 同一 PID 連續失敗幾次後停止詢問
        public var maxFailuresBeforeSkip: Int
        public var timeouts: ELM327Session.Timeouts
        public var fuel: FuelParameters

        public init(pollInterval: TimeInterval = 0.1,
                    slowPollEvery: Int = 10,
                    retryDelay: TimeInterval = 3,
                    maxFailuresBeforeSkip: Int = 3,
                    timeouts: ELM327Session.Timeouts = .init(),
                    fuel: FuelParameters = .init()) {
            self.pollInterval = pollInterval
            self.slowPollEvery = slowPollEvery
            self.retryDelay = retryDelay
            self.maxFailuresBeforeSkip = maxFailuresBeforeSkip
            self.timeouts = timeouts
            self.fuel = fuel
        }
    }

    public let kind: DataSourceKind
    private let makeTransport: @Sendable () -> OBDTransport
    private let config: Configuration
    private let telemetry = AsyncBroadcaster<TelemetrySnapshot>(initial: .empty)
    private let state = AsyncBroadcaster<ConnectionState>(initial: .disconnected)
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var trip = TripComputer()
    private var resetRequested = false
    private let clock: @Sendable () -> Date

    public init(kind: DataSourceKind = .bleOBD,
                configuration: Configuration = .init(),
                clock: @escaping @Sendable () -> Date = { Date() },
                makeTransport: @escaping @Sendable () -> OBDTransport) {
        self.kind = kind
        self.config = configuration
        self.clock = clock
        self.makeTransport = makeTransport
    }

    public func telemetryStream() -> AsyncStream<TelemetrySnapshot> { telemetry.stream() }
    public func connectionStateStream() -> AsyncStream<ConnectionState> { state.stream() }
    public var currentState: ConnectionState? { state.currentValue }
    public var latestSnapshot: TelemetrySnapshot? { telemetry.currentValue }

    public func start() {
        lock.lock()
        guard task == nil else { lock.unlock(); return }
        task = Task { [weak self] in await self?.runLoop() }
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let t = task
        task = nil
        lock.unlock()
        t?.cancel()
        state.send(.disconnected)
    }

    public func resetTrip() {
        lock.lock()
        resetRequested = true
        lock.unlock()
    }

    // MARK: - 主迴圈

    private func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let transport = makeTransport()
            let session = ELM327Session(transport: transport, timeouts: config.timeouts)
            do {
                state.send(.scanning)
                let name = try await session.open()
                state.send(.connecting(deviceName: name))
                try await connectedLoop(session: session, deviceName: name)
            } catch is CancellationError {
                // 正常停止
            } catch let error as ELM327Error {
                if !Task.isCancelled {
                    switch error {
                    case .unableToConnect, .noData, .busError:
                        state.send(.vehicleNotResponding(reason: Self.describe(error)))
                    default:
                        state.send(.failed(reason: Self.describe(error)))
                    }
                }
            } catch {
                if !Task.isCancelled { state.send(.failed(reason: String(describing: error))) }
            }
            await session.close()
            if Task.isCancelled { break }
            await sleep(config.retryDelay)
        }
    }

    /// 已連上轉接器：初始化並持續輪詢。ECU 沒回應時在同一條連線上重試初始化。
    private func connectedLoop(session: ELM327Session, deviceName: String) async throws {
        let stateRef = state
        var info: ELM327AdapterInfo
        while true {
            try Task.checkCancellation()
            do {
                info = try await session.initialize(deviceName: deviceName) { step in
                    stateRef.send(.initializing(step: step))
                }
                break
            } catch ELM327Error.unableToConnect {
                state.send(.vehicleNotResponding(reason: "UNABLE TO CONNECT"))
                await sleep(config.retryDelay)
            } catch ELM327Error.noData {
                state.send(.vehicleNotResponding(reason: "NO DATA"))
                await sleep(config.retryDelay)
            }
        }

        let detail = [info.version, info.protocolDescription, deviceName]
            .compactMap { $0 }
            .joined(separator: " · ")
        state.send(.connected(detail: detail))
        try await pollLoop(session: session, info: info)
    }

    private func pollLoop(session: ELM327Session, info: ELM327AdapterInfo) async throws {
        var failures: [OBDPID: Int] = [:]
        var snapshot = TelemetrySnapshot(timestamp: clock())
        var cycle = 0
        var useAdapterVoltage = false

        func isSupported(_ pid: OBDPID) -> Bool {
            if failures[pid, default: 0] >= config.maxFailuresBeforeSkip { return false }
            // 該 PID 所在範圍的支援遮罩若有讀到，就照遮罩判斷；否則先試試看
            let base = (pid.rawValue &- 1) / 0x20 * 0x20
            if info.queriedBitmaskBases.contains(base) {
                return info.supportedPIDs.contains(pid.rawValue)
            }
            return true
        }

        func read(_ pid: OBDPID) async throws -> Double? {
            guard isSupported(pid) else { return nil }
            do {
                let v = try await session.read(pid)
                failures[pid] = 0
                return v
            } catch let e as ELM327Error {
                switch e {
                case .noData, .malformedResponse, .unknownCommand, .stopped, .timeout:
                    failures[pid, default: 0] += 1
                    return nil
                default:
                    throw e
                }
            }
        }

        while true {
            try Task.checkCancellation()
            let fast = (cycle % max(1, config.slowPollEvery)) != 0

            snapshot.rpm = try await read(.engineRPM)
            snapshot.speedKmh = try await read(.vehicleSpeed)

            var maf = try await read(.mafAirFlow)
            if maf == nil, !isSupported(.mafAirFlow), let rpm = snapshot.rpm {
                // 備案：速度—密度法（MAP + IAT）
                if let mapKPa = try await read(.intakeManifoldPressure) {
                    let iat = try await read(.intakeAirTemperature) ?? 25
                    maf = FuelCalculator.estimatedMAF(rpm: rpm, mapKPa: mapKPa, intakeAirTempC: iat, parameters: config.fuel)
                }
            }
            snapshot.mafGramsPerSecond = maf

            if !fast {
                snapshot.coolantTempC = try await read(.coolantTemperature)
                snapshot.fuelLevelPercent = try await read(.fuelTankLevel)
                if !useAdapterVoltage {
                    snapshot.controlModuleVoltage = try await read(.controlModuleVoltage)
                    if snapshot.controlModuleVoltage == nil && !isSupported(.controlModuleVoltage) {
                        useAdapterVoltage = true
                    }
                }
                if useAdapterVoltage {
                    snapshot.controlModuleVoltage = try? await session.readAdapterVoltage()
                }
            }

            let now = clock()
            snapshot.timestamp = now
            if let maf {
                let lph = FuelCalculator.litersPerHour(mafGramsPerSecond: maf, parameters: config.fuel)
                snapshot.instantFuelLitersPerHour = lph
                snapshot.instantFuelLitersPer100km = snapshot.speedKmh.flatMap {
                    FuelCalculator.litersPer100km(litersPerHour: lph, speedKmh: $0, parameters: config.fuel)
                }
            } else {
                snapshot.instantFuelLitersPerHour = nil
                snapshot.instantFuelLitersPer100km = nil
            }

            let current = snapshot
            snapshot.trip = lock.locked {
                if resetRequested { trip.reset(); resetRequested = false }
                trip.update(speedKmh: current.speedKmh,
                            fuelLitersPerHour: current.instantFuelLitersPerHour,
                            engineRunning: (current.rpm ?? 0) > 0,
                            at: now)
                return trip.summary
            }

            telemetry.send(snapshot)
            cycle &+= 1
            await sleep(config.pollInterval)
        }
    }

    static func describe(_ error: ELM327Error) -> String {
        switch error {
        case .noData: return "NO DATA"
        case .unableToConnect: return "UNABLE TO CONNECT"
        case .unknownCommand: return "?"
        case .stopped: return "STOPPED"
        case .busError(let s): return s
        case .bufferFull: return "BUFFER FULL"
        case .adapterError(let s): return s
        case .malformedResponse(let s): return "Malformed: \(s)"
        case .commandNotAllowed(let s): return "Blocked command: \(s)"
        case .timeout(let c): return "Timeout: \(c)"
        case .notConnected: return "Not connected"
        case .busy: return "Busy"
        case .transport(let s): return s
        }
    }
}
