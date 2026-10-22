import Foundation

/// 位元組層的傳輸介面（BLE、Wi-Fi、模擬）。
///
/// 傳輸層只負責「把位元組送出去」與「把收到的位元組交上來」，
/// 完全不懂 ELM327 協定；協定邏輯在 `ELM327Session`，因此可以用 `MockOBDTransport` 測試。
public protocol OBDTransport: AnyObject, Sendable {
    /// 收到的原始位元組。每次連線呼叫一次；串流結束代表連線中斷。
    func incomingBytes() -> AsyncStream<Data>
    /// 建立連線（例如：掃描並連上 BLE 轉接器）。回傳裝置名稱。
    func connect() async throws -> String
    /// 中斷連線。
    func disconnect() async
    /// 送出位元組（呼叫端負責加上 "\r"）。
    func send(_ data: Data) async throws
}

/// 可編寫腳本的模擬傳輸層：用來做單元測試，也可在沒有硬體時展示 ELM327 流程。
///
/// `responder` 收到一條指令（已去除 "\r"），回傳 ELM327 會回的文字（不含 '>' 提示字元；
/// 會自動補上 "\r\r>"）。回傳 nil 代表轉接器「沒反應」，用來測試逾時。
public final class MockOBDTransport: OBDTransport, @unchecked Sendable {
    public typealias Responder = @Sendable (String) -> String?

    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var _sentCommands: [String] = []
    private var pendingInput = ""
    private let responder: Responder
    /// 每次回傳的分段大小（模擬 BLE 20 位元組通知），0 表示一次送完
    public var chunkSize: Int
    /// 每段之間的延遲（秒）
    public var chunkDelay: TimeInterval
    public var deviceName: String
    public var failConnect: Bool = false

    public init(deviceName: String = "Mock ELM327",
                chunkSize: Int = 0,
                chunkDelay: TimeInterval = 0,
                responder: @escaping Responder) {
        self.deviceName = deviceName
        self.chunkSize = chunkSize
        self.chunkDelay = chunkDelay
        self.responder = responder
    }

    /// 已送出的指令（測試用來驗證白名單）
    public var sentCommands: [String] {
        lock.lock(); defer { lock.unlock() }
        return _sentCommands
    }

    public func incomingBytes() -> AsyncStream<Data> {
        AsyncStream { c in
            lock.lock()
            continuation = c
            lock.unlock()
        }
    }

    public func connect() async throws -> String {
        if failConnect { throw ELM327Error.transport("mock connect failure") }
        return deviceName
    }

    public func disconnect() async {
        simulateDrop()
    }

    /// 模擬轉接器主動斷線
    public func simulateDrop() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.finish()
    }

    /// 直接注入原始位元組（測試雜訊、遲到的回應等）
    public func inject(_ text: String) {
        lock.lock()
        let c = continuation
        lock.unlock()
        c?.yield(Data(text.utf8))
    }

    public func send(_ data: Data) async throws {
        let text = String(decoding: data, as: UTF8.self)
        let commands: [String]? = lock.locked {
            guard continuation != nil else { return nil }
            var found: [String] = []
            pendingInput += text
            while let r = pendingInput.firstIndex(of: "\r") {
                found.append(String(pendingInput[..<r]))
                pendingInput = String(pendingInput[pendingInput.index(after: r)...])
            }
            _sentCommands.append(contentsOf: found)
            return found
        }
        guard let commands else { throw ELM327Error.notConnected }

        for command in commands {
            guard let reply = responder(command) else { continue }
            let full = reply + "\r\r>"
            let bytes = Array(full.utf8)
            let size = chunkSize > 0 ? chunkSize : bytes.count
            var index = 0
            while index < bytes.count {
                let end = min(index + size, bytes.count)
                if chunkDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(chunkDelay * 1_000_000_000))
                }
                let c = lock.locked { continuation }
                c?.yield(Data(bytes[index..<end]))
                index = end
            }
        }
    }
}
