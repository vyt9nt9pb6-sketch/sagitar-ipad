import Foundation

/// 可重現的亂數產生器（SplitMix64），讓模擬器在測試中結果固定。
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// 擬真的市區 / 郊區行駛模擬：怠速 → 加速 → 巡航 → 減速 → 停車，
/// 搭配 7 速 DSG 換檔、引擎暖車、充電電壓、油量消耗。
public struct DrivingSimulator: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle(remaining: TimeInterval)
        case accelerating(target: Double)
        case cruising(target: Double, remaining: TimeInterval)
        case braking(target: Double)
    }

    public private(set) var phase: Phase = .idle(remaining: 3)
    public private(set) var speedKmh: Double = 0
    public private(set) var rpm: Double = 780
    public private(set) var coolantTempC: Double
    public private(set) var voltage: Double = 14.2
    public private(set) var mafGramsPerSecond: Double = 2.6
    public private(set) var fuelLevelPercent: Double
    public private(set) var gear: Int = 1
    public var parameters: FuelParameters
    private var rng: SeededRandom
    private var accel: Double = 6 // km/h per second

    /// DSG 各檔每 km/h 的轉速（約略值）
    private static let rpmPerKmh: [Double] = [0, 125, 70, 46, 34, 27, 23, 19.5]
    private static let upshiftAt: [Double] = [0, 18, 32, 50, 65, 80, 95, .infinity]

    public init(seed: UInt64 = 2018, startCoolantC: Double = 45, fuelLevelPercent: Double = 68, parameters: FuelParameters = .init()) {
        self.rng = SeededRandom(seed: seed)
        self.coolantTempC = startCoolantC
        self.fuelLevelPercent = fuelLevelPercent
        self.parameters = parameters
    }

    private mutating func random(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &rng)
    }

    /// 前進 dt 秒。
    public mutating func step(dt: TimeInterval) {
        guard dt > 0 else { return }
        var load: Double

        switch phase {
        case .idle(let remaining):
            speedKmh = 0
            load = 0
            let left = remaining - dt
            if left <= 0 {
                let target = random(0...1) < 0.3 ? random(80...110) : random(30...70)
                accel = random(5...9)
                phase = .accelerating(target: target.rounded())
            } else {
                phase = .idle(remaining: left)
            }
        case .accelerating(let target):
            speedKmh = min(target, speedKmh + accel * dt)
            load = 0.85
            if speedKmh >= target {
                phase = .cruising(target: target, remaining: random(10...30))
            }
        case .cruising(let target, let remaining):
            speedKmh = max(0, target + random(-1.5...1.5))
            load = 0.3 + speedKmh / 400
            let left = remaining - dt
            if left <= 0 {
                let r = random(0...1)
                if r < 0.45 {
                    phase = .braking(target: 0)
                } else if r < 0.75, target > 40 {
                    phase = .braking(target: (target * random(0.4...0.7)).rounded())
                } else {
                    accel = random(4...7)
                    phase = .accelerating(target: min(120, (target + random(10...30)).rounded()))
                }
            } else {
                phase = .cruising(target: target, remaining: left)
            }
        case .braking(let target):
            speedKmh = max(target, speedKmh - random(7...11) * dt)
            load = 0.04 // 減速斷油
            if speedKmh <= target {
                if target <= 0 {
                    speedKmh = 0
                    phase = .idle(remaining: random(3...8))
                } else {
                    phase = .cruising(target: target, remaining: random(8...20))
                }
            }
        }

        // 換檔與轉速
        if speedKmh < 1 {
            gear = 1
            rpm = 780 + random(-15...15)
        } else {
            while gear < 7, speedKmh > Self.upshiftAt[gear] { gear += 1 }
            while gear > 1, speedKmh < Self.upshiftAt[gear - 1] - 6 { gear -= 1 }
            let base = speedKmh * Self.rpmPerKmh[gear]
            let boost: Double
            if case .accelerating = phase { boost = 350 } else { boost = 0 }
            rpm = max(800, min(6200, base + boost + random(-20...20)))
        }

        // 進氣量（g/s）：怠速約 2.5；其他依轉速與負載
        let idleMAF = 2.5
        let theoretical = rpm / 120 * parameters.engineDisplacementLiters * 1.2 * load
        mafGramsPerSecond = max(idleMAF * (load < 0.05 && speedKmh > 1 ? 0.6 : 1), theoretical) + random(-0.1...0.1)
        mafGramsPerSecond = max(0, mafGramsPerSecond)

        // 暖車：往 90°C 靠近，節溫器維持 88–92
        let warmRate = 0.12 + rpm / 40_000
        if coolantTempC < 89 {
            coolantTempC = min(90, coolantTempC + warmRate * dt)
        } else {
            coolantTempC = max(87, min(93, coolantTempC + random(-0.05...0.05) * dt * 10))
        }

        // 充電電壓
        voltage = max(13.6, min(14.6, voltage + random(-0.02...0.02) + (14.2 - voltage) * 0.05))

        // 油量
        let lph = FuelCalculator.litersPerHour(mafGramsPerSecond: mafGramsPerSecond, parameters: parameters)
        let usedLiters = lph * dt / 3600
        fuelLevelPercent = max(0, fuelLevelPercent - usedLiters / parameters.tankCapacityLiters * 100)
    }
}
