import Foundation

extension NSLock {
    /// 在鎖內執行（可在 async 函式中安全呼叫，因為鎖不會跨越 await）。
    @inline(__always)
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
