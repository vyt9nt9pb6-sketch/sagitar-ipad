import Foundation

/// 一次遙測資料快照。所有量測值皆為可選：ECU 不支援或讀取失敗時為 `nil`。
public struct TelemetrySnapshot: Sendable, Equatable {
    public var timestamp: Date
    /// 車速 km/h（PID 010D）
    public var speedKmh: Double?
    /// 引擎轉速 rpm（PID 010C）
    public var rpm: Double?
    /// 冷卻液溫度 °C（PID 0105）
    public var coolantTempC: Double?
    /// 控制模組電壓 V（PID 0142，或退而求其次使用 ELM327 的 ATRV）
    public var controlModuleVoltage: Double?
    /// 進氣流量 g/s（PID 0110）
    public var mafGramsPerSecond: Double?
    /// 油箱油量 %（PID 012F）
    public var fuelLevelPercent: Double?
    /// 瞬時油耗 L/h（由 MAF 推估）
    public var instantFuelLitersPerHour: Double?
    /// 瞬時油耗 L/100km（由 MAF + 車速推估；車速過低時為 nil）
    public var instantFuelLitersPer100km: Double?
    /// 行車電腦
    public var trip: TripSummary

    public init(
        timestamp: Date = Date(),
        speedKmh: Double? = nil,
        rpm: Double? = nil,
        coolantTempC: Double? = nil,
        controlModuleVoltage: Double? = nil,
        mafGramsPerSecond: Double? = nil,
        fuelLevelPercent: Double? = nil,
        instantFuelLitersPerHour: Double? = nil,
        instantFuelLitersPer100km: Double? = nil,
        trip: TripSummary = TripSummary()
    ) {
        self.timestamp = timestamp
        self.speedKmh = speedKmh
        self.rpm = rpm
        self.coolantTempC = coolantTempC
        self.controlModuleVoltage = controlModuleVoltage
        self.mafGramsPerSecond = mafGramsPerSecond
        self.fuelLevelPercent = fuelLevelPercent
        self.instantFuelLitersPerHour = instantFuelLitersPerHour
        self.instantFuelLitersPer100km = instantFuelLitersPer100km
        self.trip = trip
    }

    public static let empty = TelemetrySnapshot()
}

/// 行車電腦摘要。
public struct TripSummary: Sendable, Equatable {
    /// 里程 km
    public var distanceKm: Double
    /// 行駛時間（秒；引擎運轉中的時間）
    public var elapsedSeconds: TimeInterval
    /// 累計耗油 L（推估）
    public var fuelUsedLiters: Double

    public init(distanceKm: Double = 0, elapsedSeconds: TimeInterval = 0, fuelUsedLiters: Double = 0) {
        self.distanceKm = distanceKm
        self.elapsedSeconds = elapsedSeconds
        self.fuelUsedLiters = fuelUsedLiters
    }

    /// 平均車速 km/h
    public var averageSpeedKmh: Double? {
        guard elapsedSeconds > 1 else { return nil }
        return distanceKm / (elapsedSeconds / 3600)
    }

    /// 平均油耗 L/100km（里程太短時為 nil，避免數字亂跳）
    public var averageLitersPer100km: Double? {
        guard distanceKm >= 0.1 else { return nil }
        return fuelUsedLiters / distanceKm * 100
    }
}
