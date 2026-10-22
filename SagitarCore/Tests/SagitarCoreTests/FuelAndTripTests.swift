import XCTest
@testable import SagitarCore

final class FuelAndTripTests: XCTestCase {
    let p = FuelParameters()

    func testLitersPerHourFromMAF() {
        // 10 g/s × 3600 / (14.7 × 745) = 3.2872 L/h
        XCTAssertEqual(FuelCalculator.litersPerHour(mafGramsPerSecond: 10, parameters: p), 3.2872, accuracy: 0.0005)
        XCTAssertEqual(FuelCalculator.litersPerHour(mafGramsPerSecond: 0, parameters: p), 0)
        XCTAssertEqual(FuelCalculator.litersPerHour(mafGramsPerSecond: -1, parameters: p), 0)
    }

    func testInstantPer100km() {
        // 3.2872 L/h @ 60 km/h → 5.4787 L/100km
        let v = FuelCalculator.instantLitersPer100km(mafGramsPerSecond: 10, speedKmh: 60, parameters: p)
        XCTAssertEqual(v!, 5.4787, accuracy: 0.001)
    }

    func testInstantPer100kmNilWhenStopped() {
        XCTAssertNil(FuelCalculator.instantLitersPer100km(mafGramsPerSecond: 2.5, speedKmh: 0, parameters: p))
        XCTAssertNil(FuelCalculator.instantLitersPer100km(mafGramsPerSecond: 2.5, speedKmh: 4.9, parameters: p))
        XCTAssertNotNil(FuelCalculator.instantLitersPer100km(mafGramsPerSecond: 2.5, speedKmh: 5, parameters: p))
    }

    func testCalibrationFactor() {
        var q = p
        q.calibrationFactor = 1.1
        XCTAssertEqual(FuelCalculator.litersPerHour(mafGramsPerSecond: 10, parameters: q),
                       FuelCalculator.litersPerHour(mafGramsPerSecond: 10, parameters: p) * 1.1, accuracy: 1e-9)
    }

    func testSpeedDensityEstimate() {
        // 1.4 L、VE 0.85、2000 rpm、MAP 100 kPa、25°C
        // ρ = 100000 / (287.05 × 298.15) = 1.1685 kg/m³
        // ṁ = 1.1685 × 0.0014 × 0.85 × 2000/120 = 0.023175 kg/s = 23.18 g/s
        let maf = FuelCalculator.estimatedMAF(rpm: 2000, mapKPa: 100, intakeAirTempC: 25, parameters: p)
        XCTAssertEqual(maf, 23.18, accuracy: 0.05)
        XCTAssertEqual(FuelCalculator.estimatedMAF(rpm: 0, mapKPa: 100, intakeAirTempC: 25), 0)
    }

    func testTripComputerIntegration() {
        var trip = TripComputer()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // 以 60 km/h、3.6 L/h 開 1 小時（每秒一筆）
        for i in 0...3600 {
            trip.update(speedKmh: 60, fuelLitersPerHour: 3.6, engineRunning: true, at: t0.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(trip.summary.distanceKm, 60, accuracy: 0.001)
        XCTAssertEqual(trip.summary.elapsedSeconds, 3600, accuracy: 0.001)
        XCTAssertEqual(trip.summary.fuelUsedLiters, 3.6, accuracy: 0.001)
        XCTAssertEqual(trip.summary.averageSpeedKmh!, 60, accuracy: 0.001)
        XCTAssertEqual(trip.summary.averageLitersPer100km!, 6.0, accuracy: 0.001)
    }

    func testTripComputerIgnoresGapsAndIdleDistance() {
        var trip = TripComputer()
        let t0 = Date(timeIntervalSince1970: 0)
        trip.update(speedKmh: 0, fuelLitersPerHour: 0.8, engineRunning: true, at: t0)
        trip.update(speedKmh: 0, fuelLitersPerHour: 0.8, engineRunning: true, at: t0.addingTimeInterval(1))
        XCTAssertEqual(trip.summary.distanceKm, 0)
        XCTAssertEqual(trip.summary.elapsedSeconds, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(trip.summary.fuelUsedLiters, 0)
        XCTAssertNil(trip.summary.averageLitersPer100km) // 里程 < 0.1 km
        // 斷線 60 秒：這段不積分
        trip.update(speedKmh: 100, fuelLitersPerHour: 6, engineRunning: true, at: t0.addingTimeInterval(61))
        XCTAssertEqual(trip.summary.distanceKm, 0)
        XCTAssertEqual(trip.summary.elapsedSeconds, 1, accuracy: 1e-9)
        trip.reset()
        XCTAssertEqual(trip.summary, TripSummary())
    }

    func testTripSummaryAverages() {
        XCTAssertNil(TripSummary().averageSpeedKmh)
        let s = TripSummary(distanceKm: 12.5, elapsedSeconds: 1800, fuelUsedLiters: 0.9)
        XCTAssertEqual(s.averageSpeedKmh!, 25, accuracy: 1e-9)
        XCTAssertEqual(s.averageLitersPer100km!, 7.2, accuracy: 1e-9)
    }
}
