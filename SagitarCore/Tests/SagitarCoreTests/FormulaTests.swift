import XCTest
@testable import SagitarCore

final class FormulaTests: XCTestCase {
    func testRPM() {
        XCTAssertEqual(OBDFormulas.rpm(a: 0x1A, b: 0xF8), 1726)
        XCTAssertEqual(OBDFormulas.rpm(a: 0, b: 0), 0)
        XCTAssertEqual(OBDFormulas.rpm(a: 0xFF, b: 0xFF), 16383.75)
        XCTAssertEqual(OBDPID.engineRPM.decode([0x0C, 0x30]), 780)
    }

    func testSpeed() {
        XCTAssertEqual(OBDPID.vehicleSpeed.decode([0x00]), 0)
        XCTAssertEqual(OBDPID.vehicleSpeed.decode([0xFF]), 255)
    }

    func testCoolant() {
        XCTAssertEqual(OBDPID.coolantTemperature.decode([0x00]), -40)
        XCTAssertEqual(OBDPID.coolantTemperature.decode([0x82]), 90)
        XCTAssertEqual(OBDPID.coolantTemperature.decode([0xFF]), 215)
    }

    func testControlModuleVoltage() {
        XCTAssertEqual(OBDPID.controlModuleVoltage.decode([0x37, 0x6E])!, 14.19, accuracy: 0.0001)
        XCTAssertEqual(OBDPID.controlModuleVoltage.decode([0x31, 0x38])!, 12.6, accuracy: 0.0001)
    }

    func testFuelLevel() {
        XCTAssertEqual(OBDPID.fuelTankLevel.decode([0x00]), 0)
        XCTAssertEqual(OBDPID.fuelTankLevel.decode([0xFF]), 100)
        XCTAssertEqual(OBDPID.fuelTankLevel.decode([0x80])!, 50.196, accuracy: 0.001)
    }

    func testMAF() {
        XCTAssertEqual(OBDPID.mafAirFlow.decode([0x03, 0xE8]), 10)
        XCTAssertEqual(OBDPID.mafAirFlow.decode([0x00, 0xFA]), 2.5)
    }

    func testMAPAndIAT() {
        XCTAssertEqual(OBDPID.intakeManifoldPressure.decode([0x65]), 101)
        XCTAssertEqual(OBDPID.intakeAirTemperature.decode([0x41]), 25)
    }

    func testDecodeTooFewBytes() {
        XCTAssertNil(OBDPID.engineRPM.decode([0x1A]))
        XCTAssertNil(OBDPID.vehicleSpeed.decode([]))
    }

    func testCommandStrings() {
        XCTAssertEqual(OBDPID.engineRPM.command, "010C")
        XCTAssertEqual(OBDPID.controlModuleVoltage.command, "0142")
        XCTAssertEqual(OBDPID.supported01to20.command, "0100")
    }

    func testSupportedPIDBitmask() {
        // 維基百科範例：BE 1F A8 13
        let set = OBDFormulas.supportedPIDs(base: 0x00, bitmask: [0xBE, 0x1F, 0xA8, 0x13])
        XCTAssertEqual(set, [0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20])
    }

    func testSupportedPIDBitmaskOffsetBase() {
        let set = OBDFormulas.supportedPIDs(base: 0x40, bitmask: [0x40, 0x00, 0x00, 0x00])
        XCTAssertEqual(set, [0x42])
        XCTAssertEqual(OBDFormulas.supportedPIDs(base: 0x20, bitmask: [0x00, 0x02, 0x00, 0x01]), [0x2F, 0x40])
        XCTAssertEqual(OBDFormulas.supportedPIDs(base: 0, bitmask: [0x01]), [])
    }
}
