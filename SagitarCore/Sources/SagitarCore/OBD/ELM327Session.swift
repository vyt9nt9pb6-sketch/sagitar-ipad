import Foundation

/// 轉接器資訊（初始化後取得）。
public struct ELM327AdapterInfo: Equatable, Sendable {
    public var deviceName: String
    public var version: String?
    public var protocolDescription: String?
    public var supportedPIDs: Set<UInt8>
    /// 成功讀到支援遮罩的範圍起點（0x00、0x20、0x40）
    public var queriedBitmaskBases: Set<UInt8>

    public init(deviceName: String, version: String? = nil, protocolDescription: String? = nil,
                supportedPIDs: Set<UInt8> = [], queriedBitmaskBases: Set<UInt8> = []) {
        self.deviceName = deviceName
        self.version = version
        self.protocolDescription = protocolDescription
        self.supportedPIDs = supportedPIDs
        self.queriedBitmaskBases = queriedBitmaskBases
    }
}

/// ELM327 協定工作階段：
/// - 指令一律先經過 `OBDCommandWhitelist`，不在白名單的指令**不會**送到傳輸層
/// - 一次只送一條指令，收到 '>' 提示字元才算完成（回應會被分段送來，例如 BLE 每次 20 位元組）
/// - 逾時保護
public actor ELM327Session {
    public struct Timeouts: Sendable {
        /// 一般指令
        public var command: TimeInterval
        /// ATZ 重置
        public var reset: TimeInterval
        /// 第一次查詢（ATSP0 自動搜尋協定時可能要好幾秒）
        public var protocolSearch: TimeInterval

        public init(command: TimeInterval = 2.0, reset: TimeInterval = 5.0, protocolSearch: TimeInterval = 12.0) {
            self.command = command
            self.reset = reset
            self.protocolSearch = protocolSearch
        }
    }

    /// 初始化指令序列（皆為唯讀的轉接器設定）。
    public static let initSequence = ["ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"]

    private let transport: OBDTransport
    private let timeouts: Timeouts
    private var buffer = ""
    private var pending: CheckedContinuation<String, Error>?
    private var pendingToken = 0
    private var pendingCommand = ""
    private var readerTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isOpen = false
    private var readerGeneration = 0
    /// 上一條指令逾時：轉接器可能稍後才送來遲到的回應，下一條指令前要先清掉
    private var hadTimeout = false
    public private(set) var info: ELM327AdapterInfo?

    public init(transport: OBDTransport, timeouts: Timeouts = Timeouts()) {
        self.transport = transport
        self.timeouts = timeouts
    }

    // MARK: - 連線

    /// 建立傳輸層連線，回傳裝置名稱。
    @discardableResult
    public func open() async throws -> String {
        let stream = transport.incomingBytes()
        readerTask?.cancel()
        readerGeneration &+= 1
        let generation = readerGeneration
        readerTask = Task { [weak self] in
            for await chunk in stream {
                await self?.receive(chunk)
            }
            await self?.transportClosed(generation: generation)
        }
        do {
            let name = try await transport.connect()
            isOpen = true
            return name
        } catch {
            readerTask?.cancel()
            readerTask = nil
            throw error
        }
    }

    public func close() async {
        isOpen = false
        readerTask?.cancel()
        readerTask = nil
        failPending(ELM327Error.notConnected)
        await transport.disconnect()
    }

    /// 送出初始化序列，並以 0100 觸發協定搜尋、讀取支援的 PID。
    public func initialize(deviceName: String, progress: (@Sendable (String) -> Void)? = nil) async throws -> ELM327AdapterInfo {
        var info = ELM327AdapterInfo(deviceName: deviceName)

        progress?("ATZ")
        let resetRaw = try await send("ATZ", timeout: timeouts.reset)
        let resetLines = try ELM327ResponseParser.atResponse(raw: resetRaw, command: "ATZ")
        info.version = resetLines.first(where: { $0.contains("ELM") }) ?? resetLines.last

        for cmd in ["ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"] {
            progress?(cmd)
            let raw = try await send(cmd)
            try ELM327ResponseParser.expectOK(raw: raw, command: cmd)
        }

        // 第一次查詢會觸發協定搜尋（"SEARCHING..."）；ECU 沒回應時會得到 UNABLE TO CONNECT。
        progress?("0100")
        let raw = try await send(OBDPID.supported01to20.command, timeout: timeouts.protocolSearch)
        info.supportedPIDs = try ELM327ResponseParser.supportedPIDs(raw: raw, base: 0x00)
        info.queriedBitmaskBases.insert(0x00)

        // 有支援 0x20 才問 0120；有 0x40 才問 0140
        if info.supportedPIDs.contains(0x20) {
            progress?("0120")
            if let r = try? await send(OBDPID.supported21to40.command),
               let s = try? ELM327ResponseParser.supportedPIDs(raw: r, base: 0x20) {
                info.supportedPIDs.formUnion(s)
                info.queriedBitmaskBases.insert(0x20)
                if s.contains(0x40),
                   let r2 = try? await send(OBDPID.supported41to60.command),
                   let s2 = try? ELM327ResponseParser.supportedPIDs(raw: r2, base: 0x40) {
                    info.supportedPIDs.formUnion(s2)
                    info.queriedBitmaskBases.insert(0x40)
                }
            }
        }

        progress?("ATDP")
        if let dp = try? await send("ATDP"),
           let lines = try? ELM327ResponseParser.atResponse(raw: dp, command: "ATDP") {
            info.protocolDescription = lines.first
        }
        self.info = info
        return info
    }

    // MARK: - 查詢

    /// 讀取一個 PID 並換算成工程單位。遇到 STOPPED 會重試一次。
    public func read(_ pid: OBDPID) async throws -> Double {
        do {
            let raw = try await send(pid.command)
            return try ELM327ResponseParser.value(for: pid, raw: raw)
        } catch ELM327Error.stopped {
            let raw = try await send(pid.command)
            return try ELM327ResponseParser.value(for: pid, raw: raw)
        }
    }

    /// 讀取轉接器量測的電壓（ATRV），在 0142 不支援時當作備案。
    public func readAdapterVoltage() async throws -> Double {
        let raw = try await send("ATRV")
        return try ELM327ResponseParser.adapterVoltage(raw: raw)
    }

    /// 送出一條指令，等待 '>' 提示字元並回傳原始回應文字（不含 '>'）。
    /// 不在白名單內的指令會直接丟出 `.commandNotAllowed`，不會碰到傳輸層。
    public func send(_ command: String, timeout: TimeInterval? = nil) async throws -> String {
        guard OBDCommandWhitelist.isAllowed(command) else {
            throw ELM327Error.commandNotAllowed(command)
        }
        guard isOpen else { throw ELM327Error.notConnected }
        guard pending == nil else { throw ELM327Error.busy }

        if hadTimeout {
            // 給遲到的回應一點時間抵達，然後丟棄
            hadTimeout = false
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        buffer = ""

        let normalized = OBDCommandWhitelist.normalize(command)
        let payload = Data((normalized + "\r").utf8)
        pendingToken &+= 1
        let token = pendingToken
        pendingCommand = normalized
        let limit = timeout ?? timeouts.command

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.pending = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
                await self?.timeoutFired(token: token)
            }
            let transport = self.transport
            Task { [weak self] in
                do {
                    try await transport.send(payload)
                } catch {
                    await self?.writeFailed(token: token, error: error)
                }
            }
        }
    }

    // MARK: - 內部

    private func receive(_ chunk: Data) {
        buffer += String(decoding: chunk, as: UTF8.self)
        while let prompt = buffer.firstIndex(of: ">") {
            let response = String(buffer[..<prompt])
            buffer = String(buffer[buffer.index(after: prompt)...])
            if let p = pending {
                pending = nil
                timeoutTask?.cancel()
                timeoutTask = nil
                p.resume(returning: response)
            }
            // 沒有等待中的指令：丟棄（雜訊或遲到的回應）
        }
        // 防呆：緩衝區無限成長（轉接器在 MA 模式狂吐資料等）
        if buffer.count > 4096 { buffer = String(buffer.suffix(1024)) }
    }

    private func timeoutFired(token: Int) {
        guard token == pendingToken, let p = pending else { return }
        pending = nil
        timeoutTask = nil
        hadTimeout = true
        p.resume(throwing: ELM327Error.timeout(command: pendingCommand))
    }

    private func writeFailed(token: Int, error: Error) {
        guard token == pendingToken else { return }
        let mapped = (error as? ELM327Error) ?? ELM327Error.transport(String(describing: error))
        failPending(mapped)
    }

    private func failPending(_ error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let p = pending {
            pending = nil
            p.resume(throwing: error)
        }
    }

    private func transportClosed(generation: Int) {
        guard generation == readerGeneration else { return }
        isOpen = false
        failPending(ELM327Error.notConnected)
    }

    public var connected: Bool { isOpen }
}
