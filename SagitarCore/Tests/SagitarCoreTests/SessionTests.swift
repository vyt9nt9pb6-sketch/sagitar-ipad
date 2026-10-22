import XCTest
@testable import SagitarCore

final class SessionTests: XCTestCase {

    private func fastTimeouts() -> ELM327Session.Timeouts {
        .init(command: 0.3, reset: 0.5, protocolSearch: 0.5)
    }

    func testFullInitSequenceAndRead() async throws {
        let emu = ELM327Emulator()
        let transport = emu.makeTransport()
        let session = ELM327Session(transport: transport, timeouts: fastTimeouts())
        let name = try await session.open()
        XCTAssertEqual(name, "Mock ELM327")
        let info = try await session.initialize(deviceName: name)
        XCTAssertEqual(info.version, "ELM327 V1.5")
        XCTAssertEqual(info.protocolDescription, "AUTO, ISO 15765-4 (CAN 11/500)")
        XCTAssertTrue(info.supportedPIDs.isSuperset(of: [0x05, 0x0C, 0x0D, 0x10, 0x2F, 0x42]))
        XCTAssertEqual(info.queriedBitmaskBases, [0x00, 0x20, 0x40])

        let sent = transport.sentCommands
        XCTAssertEqual(Array(sent.prefix(6)), ["ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"])
        XCTAssertEqual(Array(sent.dropFirst(6)), ["0100", "0120", "0140", "ATDP"])

        let rpm = try await session.read(.engineRPM)
        XCTAssertEqual(rpm, 1726)
        let speed = try await session.read(.vehicleSpeed)
        XCTAssertEqual(speed, 60)
        let v = try await session.read(.controlModuleVoltage)
        XCTAssertEqual(v, 14.19, accuracy: 0.0001)
        let adapterV = try await session.readAdapterVoltage()
        XCTAssertEqual(adapterV, 12.6, accuracy: 0.0001)
        await session.close()
    }

    func testResponseBufferingAcrossSmallChunks() async throws {
        // BLE 通知常常一次只有幾個位元組，'>' 可能在任何一段
        let emu = ELM327Emulator()
        for size in [1, 3, 7, 20] {
            let transport = emu.makeTransport(chunkSize: size)
            let session = ELM327Session(transport: transport, timeouts: fastTimeouts())
            try await session.open()
            _ = try await session.initialize(deviceName: "x")
            let maf = try await session.read(.mafAirFlow)
            XCTAssertEqual(maf, 10, "chunk size \(size)")
            await session.close()
        }
    }

    func testBlockedCommandNeverReachesTransport() async throws {
        let emu = ELM327Emulator()
        let transport = emu.makeTransport()
        let session = ELM327Session(transport: transport, timeouts: fastTimeouts())
        try await session.open()
        for bad in ["04", "AT SH 7E0", "ATMA", "0902", "010C\r04"] {
            do {
                _ = try await session.send(bad)
                XCTFail("should have thrown for \(bad)")
            } catch ELM327Error.commandNotAllowed(let c) {
                XCTAssertEqual(c, bad)
            }
        }
        XCTAssertTrue(transport.sentCommands.isEmpty, "\(transport.sentCommands)")
        await session.close()
    }

    func testTimeoutWhenAdapterSilent() async throws {
        let transport = MockOBDTransport { _ in nil }
        let session = ELM327Session(transport: transport, timeouts: fastTimeouts())
        try await session.open()
        let start = Date()
        do {
            _ = try await session.send("ATZ", timeout: 0.2)
            XCTFail("expected timeout")
        } catch ELM327Error.timeout(let cmd) {
            XCTAssertEqual(cmd, "ATZ")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        await session.close()
    }

    func testLateResponseAfterTimeoutIsDiscarded() async throws {
        let emu = ELM327Emulator()
        emu.set { $0.echo = false }
        let transport = emu.makeTransport()
        let session = ELM327Session(transport: transport, timeouts: fastTimeouts())
        try await session.open()
        // 模擬：送出前先有雜訊與一個不屬於任何指令的 '>'
        transport.inject("41 0D FF\r\r>")
        try await Task.sleep(nanoseconds: 50_000_000)
        let speed = try await session.read(.vehicleSpeed)
        XCTAssertEqual(speed, 60)
        await session.close()
    }

    func testUnableToConnectDuringInit() async throws {
        let emu = ELM327Emulator()
        emu.set { $0.vehicleConnected = false }
        let session = ELM327Session(transport: emu.makeTransport(), timeouts: fastTimeouts())
        try await session.open()
        do {
            _ = try await session.initialize(deviceName: "x")
            XCTFail("expected UNABLE TO CONNECT")
        } catch ELM327Error.unableToConnect {}
        await session.close()
    }

    func testNoDataForUnsupportedPID() async throws {
        let emu = ELM327Emulator()
        emu.set { $0.values[0x10] = nil }
        let session = ELM327Session(transport: emu.makeTransport(), timeouts: fastTimeouts())
        try await session.open()
        _ = try await session.initialize(deviceName: "x")
        do {
            _ = try await session.read(.mafAirFlow)
            XCTFail("expected NO DATA")
        } catch ELM327Error.noData {}
        await session.close()
    }

    func testStoppedIsRetriedOnce() async throws {
        let emu = ELM327Emulator()
        let transport = emu.makeTransport()
        let session = ELM327Session(transport: transport, timeouts: fastTimeouts())
        try await session.open()
        _ = try await session.initialize(deviceName: "x")
        emu.set { $0.stopNext = true }
        let rpm = try await session.read(.engineRPM)
        XCTAssertEqual(rpm, 1726)
        XCTAssertEqual(transport.sentCommands.suffix(2), ["010C", "010C"])
        await session.close()
    }

    func testWorksWithSpacesAndHeadersOnAdapter() async throws {
        // 有些仿製品忽略 ATS0 / ATH0
        let emu = ELM327Emulator()
        let transport = MockOBDTransport { cmd in
            let r = emu.respond(cmd)
            emu.set { $0.spaces = true; $0.headers = true }
            return r
        }
        let session = ELM327Session(transport: transport, timeouts: fastTimeouts())
        try await session.open()
        _ = try await session.initialize(deviceName: "x")
        let rpm = try await session.read(.engineRPM)
        XCTAssertEqual(rpm, 1726)
        await session.close()
    }

    func testTransportDropFailsPendingCommand() async throws {
        let transport = MockOBDTransport { _ in nil }
        let session = ELM327Session(transport: transport, timeouts: .init(command: 5, reset: 5, protocolSearch: 5))
        try await session.open()
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            transport.simulateDrop()
        }
        do {
            _ = try await session.send("ATI")
            XCTFail("expected notConnected")
        } catch ELM327Error.notConnected {}
        let connected = await session.connected
        XCTAssertFalse(connected)
        do {
            _ = try await session.send("ATI")
            XCTFail("expected notConnected")
        } catch ELM327Error.notConnected {}
    }
}
