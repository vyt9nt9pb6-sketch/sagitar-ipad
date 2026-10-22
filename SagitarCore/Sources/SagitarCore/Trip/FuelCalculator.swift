import Foundation

/// 油耗推估參數。OBD-II 標準 PID 沒有「噴油量」，只能由進氣量反推：
/// 燃油質量流量 = 空氣質量流量 / 空燃比；體積 = 質量 / 汽油密度。
/// 這是**估計值**，與原廠儀表的油耗會有誤差（約 ±10–15%），可在設定中用校正係數修正。
public struct FuelParameters: Sendable, Equatable, Codable {
    /// 化學計量空燃比（汽油 14.7:1）
    public var airFuelRatio: Double
    /// 汽油密度 g/L（約 720–775，預設 745）
    public var fuelDensityGramsPerLiter: Double
    /// 校正係數（實際加油量 / App 推估量）
    public var calibrationFactor: Double
    /// 低於此車速不計算 L/100km（改顯示 L/h）
    public var minimumSpeedKmhForPer100km: Double
    /// 引擎排氣量 L（MAF 不支援時用 MAP 推估進氣量；Sagitar 常見 1.2T / 1.4T / 1.6）
    public var engineDisplacementLiters: Double
    /// 容積效率（MAP 推估用，預設 0.85）
    public var volumetricEfficiency: Double
    /// 油箱容量 L（Sagitar 約 55 L）
    public var tankCapacityLiters: Double

    public init(airFuelRatio: Double = 14.7,
                fuelDensityGramsPerLiter: Double = 745,
                calibrationFactor: Double = 1.0,
                minimumSpeedKmhForPer100km: Double = 5,
                engineDisplacementLiters: Double = 1.4,
                volumetricEfficiency: Double = 0.85,
                tankCapacityLiters: Double = 55) {
        self.airFuelRatio = airFuelRatio
        self.fuelDensityGramsPerLiter = fuelDensityGramsPerLiter
        self.calibrationFactor = calibrationFactor
        self.minimumSpeedKmhForPer100km = minimumSpeedKmhForPer100km
        self.engineDisplacementLiters = engineDisplacementLiters
        self.volumetricEfficiency = volumetricEfficiency
        self.tankCapacityLiters = tankCapacityLiters
    }

    public static let sagitar14T = FuelParameters()
}

public enum FuelCalculator {
    /// 由 MAF（g/s）推估油耗 L/h。
    /// L/h = MAF × 3600 / (AFR × 密度) × 校正係數
    public static func litersPerHour(mafGramsPerSecond maf: Double, parameters p: FuelParameters = .init()) -> Double {
        guard maf > 0, p.airFuelRatio > 0, p.fuelDensityGramsPerLiter > 0 else { return 0 }
        return maf * 3600 / (p.airFuelRatio * p.fuelDensityGramsPerLiter) * p.calibrationFactor
    }

    /// 瞬時油耗 L/100km = (L/h) / (km/h) × 100；車速太低回傳 nil（避免無限大）。
    public static func litersPer100km(litersPerHour lph: Double, speedKmh: Double, parameters p: FuelParameters = .init()) -> Double? {
        guard speedKmh >= p.minimumSpeedKmhForPer100km else { return nil }
        return lph / speedKmh * 100
    }

    /// 直接由 MAF + 車速算 L/100km。
    public static func instantLitersPer100km(mafGramsPerSecond maf: Double, speedKmh: Double, parameters p: FuelParameters = .init()) -> Double? {
        litersPer100km(litersPerHour: litersPerHour(mafGramsPerSecond: maf, parameters: p), speedKmh: speedKmh, parameters: p)
    }

    /// 「速度—密度法」推估 MAF（g/s），給不支援 PID 0110 的 ECU 使用（許多 VW TSI 引擎用 MAP 感知器）。
    /// 空氣密度 ρ = P / (R·T)；每秒進氣量 = ρ × 排氣量 × VE × rpm/120（四行程）。
    public static func estimatedMAF(rpm: Double, mapKPa: Double, intakeAirTempC: Double, parameters p: FuelParameters = .init()) -> Double {
        guard rpm > 0, mapKPa > 0 else { return 0 }
        let rSpecificAir = 287.05 // J/(kg·K)
        let tempK = intakeAirTempC + 273.15
        let densityKgPerM3 = mapKPa * 1000 / (rSpecificAir * tempK)
        let displacementM3 = p.engineDisplacementLiters / 1000
        let kgPerSecond = densityKgPerM3 * displacementM3 * p.volumetricEfficiency * rpm / 120
        return kgPerSecond * 1000
    }
}
