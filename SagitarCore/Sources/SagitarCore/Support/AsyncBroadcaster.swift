import Foundation

/// 將一個值廣播給多個 `AsyncStream` 訂閱者；會把最新值重播給新訂閱者。
public final class AsyncBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var latest: Element?

    public init(initial: Element? = nil) {
        self.latest = initial
    }

    public var currentValue: Element? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    public func stream() -> AsyncStream<Element> {
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let current = latest
            lock.unlock()
            if let current { continuation.yield(current) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    public func send(_ value: Element) {
        lock.lock()
        latest = value
        let targets = Array(continuations.values)
        lock.unlock()
        for c in targets { c.yield(value) }
    }

    public func finish() {
        lock.lock()
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for c in targets { c.finish() }
    }
}
