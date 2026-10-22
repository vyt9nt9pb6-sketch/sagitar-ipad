import Foundation

/// 行車電腦：以時間積分車速與油耗。純值型別，方便測試。
public struct TripComputer: Sendable, Equatable {
    public private(set) var summary = TripSummary()
    private var lastUpdate: Date?
    /// 兩次更新間隔超過這個秒數視為資料中斷，不積分（避免斷線後一次加上一大段）
    public var maximumGapSeconds: TimeInterval = 5

    public init() {}

    public mutating func reset() {
        summary = TripSummary()
        lastUpdate = nil
    }

    /// 加入一筆量測。
    /// - Parameters:
    ///   - speedKmh: 車速
    ///   - fuelLitersPerHour: 推估油耗（L/h）
    ///   - engineRunning: 引擎是否運轉（rpm > 0）；沒運轉時不計時間
    ///   - time: 量測時間
    public mutating func update(speedKmh: Double?, fuelLitersPerHour: Double?, engineRunning: Bool, at time: Date) {
        defer { lastUpdate = time }
        guard let last = lastUpdate else { return }
        let dt = time.timeIntervalSince(last)
        guard dt > 0, dt <= maximumGapSeconds else { return }
        if engineRunning || (speedKmh ?? 0) > 0 {
            summary.elapsedSeconds += dt
        }
        if let v = speedKmh, v > 0 {
            summary.distanceKm += v * dt / 3600
        }
        if let f = fuelLitersPerHour, f > 0 {
            summary.fuelUsedLiters += f * dt / 3600
        }
    }
}
