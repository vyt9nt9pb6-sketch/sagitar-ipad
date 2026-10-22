import XCTest
@testable import SagitarCore

final class ParserTests: XCTestCase {

    // MARK: 空白 / 無空白

    func testRPMWithSpaces() throws {
        XCTAssertEqual(try ELM327ResponseParser.value(for: .engineRPM, raw: "41 0C 1A F8 \r\r>"), 1726)
    }

    func testRPMWithoutSpaces() throws {
        XCTAssertEqual(try ELM327ResponseParser.value(for: .engineRPM, raw: "410C1AF8\r\r>"), 1726)
    }

    func testLowercaseAndLFLineEndings() throws {
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: "41 0d 3c\n\n>"), 60)
    }

    // MARK: 回顯

    func testEchoLineIsIgnored() throws {
        let raw = "010D\r41 0D 3C\r\r>"
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: raw), 60)
    }

    func testEchoWithSpacesIsIgnored() throws {
        let raw = "01 0D\r410D3C\r\r"
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: raw), 60)
    }

    func testEchoGluedToDataOnSameLine() throws {
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: "010D410D3C\r>"), 60)
    }

    func testATZEchoAndVersion() throws {
        let lines = try ELM327ResponseParser.atResponse(raw: "ATZ\r\r\rELM327 v1.5\r\r", command: "ATZ")
        XCTAssertEqual(lines, ["ELM327 V1.5"])
    }

    // MARK: 協定搜尋訊息

    func testSearchingPrefix() throws {
        let raw = "SEARCHING...\r41 05 7B\r\r>"
        XCTAssertEqual(try ELM327ResponseParser.value(for: .coolantTemperature, raw: raw), 83)
    }

    func testSearchingWithEcho() throws {
        let raw = "0105\rSEARCHING...\r41057B\r\r>"
        XCTAssertEqual(try ELM327ResponseParser.value(for: .coolantTemperature, raw: raw), 83)
    }

    func testBusInitOK() throws {
        let raw = "BUS INIT: ...OK\r41 0D 00\r\r>"
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: raw), 0)
    }

    func testBusInitOKSameLineData() throws {
        let raw = "BUS INIT: ...OK 41 0D 05\r>"
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: raw), 5)
    }

    // MARK: 錯誤字串

    func testNoData() {
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .mafAirFlow, raw: "NO DATA\r\r>")) {
            XCTAssertEqual($0 as? ELM327Error, .noData)
        }
    }

    func testSearchingThenUnableToConnect() {
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "SEARCHING...\rUNABLE TO CONNECT\r\r>")) {
            XCTAssertEqual($0 as? ELM327Error, .unableToConnect)
        }
    }

    func testQuestionMark() {
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "?\r\r>")) {
            XCTAssertEqual($0 as? ELM327Error, .unknownCommand)
        }
        XCTAssertThrowsError(try ELM327ResponseParser.expectOK(raw: "ATSP0\r?\r>", command: "ATSP0")) {
            XCTAssertEqual($0 as? ELM327Error, .unknownCommand)
        }
    }

    func testStopped() {
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "STOPPED\r\r>")) {
            XCTAssertEqual($0 as? ELM327Error, .stopped)
        }
    }

    func testBusInitError() {
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "BUS INIT: ...ERROR\r\r>")) {
            XCTAssertEqual($0 as? ELM327Error, .busError("BUS INIT: ...ERROR"))
        }
    }

    func testCanErrorAndBufferFull() {
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "CAN ERROR\r>")) {
            XCTAssertEqual($0 as? ELM327Error, .busError("CAN ERROR"))
        }
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "BUFFER FULL\r>")) {
            XCTAssertEqual($0 as? ELM327Error, .bufferFull)
        }
    }

    func testDataErrorSuffixLineIsRejected() {
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "41 0C 1A F8 <DATA ERROR\r>"))
    }

    func testGarbageIsMalformed() {
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "HELLO\r>")) {
            guard case .malformedResponse = $0 as? ELM327Error else { return XCTFail("\($0)") }
        }
    }

    func testWrongPIDIsMalformed() {
        // 回的是 0D 不是 0C
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "41 0D 3C\r>"))
    }

    func testTooFewBytes() {
        XCTAssertThrowsError(try ELM327ResponseParser.value(for: .engineRPM, raw: "41 0C 1A\r>"))
    }

    func testNulBytesAreIgnored() throws {
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: "\0\041 0D 64\r\0>"), 100)
    }

    // MARK: 多個 ECU / 多行

    func testMultipleECUsWithoutHeadersTakesFirst() throws {
        let raw = "41 0D 3C\r41 0D 3D\r\r>"
        let all = try ELM327ResponseParser.ecuResponses(raw: raw, pid: 0x0D)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: raw), 60)
    }

    func testMultipleECUsWithHeadersPrefersEngine7E8() throws {
        let raw = "7E9 03 41 0D 3D\r7E8 03 41 0D 3C\r\r>"
        let all = try ELM327ResponseParser.ecuResponses(raw: raw, pid: 0x0D)
        XCTAssertEqual(all.map(\.header), ["7E9", "7E8"])
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: raw), 60)
    }

    func testHeadersWithoutSpaces() throws {
        XCTAssertEqual(try ELM327ResponseParser.value(for: .engineRPM, raw: "7E804410C1AF8\r>"), 1726)
    }

    func testSupportedPIDsUnionAcrossECUs() throws {
        // 引擎 ECU 與變速箱 ECU 各回一份遮罩
        let raw = "41 00 BE 3E B8 11\r41 00 80 18 00 01\r>"
        let set = try ELM327ResponseParser.supportedPIDs(raw: raw, base: 0x00)
        XCTAssertTrue(set.contains(0x0C))
        XCTAssertTrue(set.contains(0x14)) // 只在第二個 ECU
        XCTAssertTrue(set.contains(0x20))
    }

    func testOneECUNoDataOtherECUData() throws {
        // 混合：一行錯誤、一行資料 → 取資料
        XCTAssertEqual(try ELM327ResponseParser.value(for: .vehicleSpeed, raw: "NO DATA\r41 0D 3C\r>"), 60)
    }

    // MARK: 多訊框（ISO-TP）

    func testMultiFrameWithLengthLine() throws {
        // 0100 回應被分成多個訊框（某些 ECU 一次回多個 PID 時會這樣）
        let raw = "00A\r0: 41 00 BE 3E B8\r1: 11 00 00 00 00 00 00\r\r>"
        let data = try ELM327ResponseParser.mode01Data(raw: raw, pid: 0x00, minimumBytes: 4)
        // 長度 0x00A = 10 位元組 → 41 00 + 8 個資料位元組
        XCTAssertEqual(data, [0xBE, 0x3E, 0xB8, 0x11, 0x00, 0x00, 0x00, 0x00])
        let set = try ELM327ResponseParser.supportedPIDs(raw: raw, base: 0x00)
        XCTAssertTrue(set.contains(0x0C))
        XCTAssertTrue(set.contains(0x0D))
    }

    func testMultiFrameWithoutSpacesNoLength() throws {
        let raw = "0:410C1A\r1:F8\r>"
        XCTAssertEqual(try ELM327ResponseParser.value(for: .engineRPM, raw: raw), 1726)
    }

    func testMultiFrameFollowedBySingleFrame() throws {
        let raw = "008\r0: 41 0C 1A F8 00\r1: 00 00\r41 0C 1B 00\r>"
        let all = try ELM327ResponseParser.ecuResponses(raw: raw, pid: 0x0C)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].data, [0x1A, 0xF8, 0x00, 0x00, 0x00])
        XCTAssertEqual(all[1].data, [0x1B, 0x00])
    }

    // MARK: AT 指令

    func testExpectOK() throws {
        XCTAssertNoThrow(try ELM327ResponseParser.expectOK(raw: "ATE0\rOK\r\r>", command: "ATE0"))
        XCTAssertNoThrow(try ELM327ResponseParser.expectOK(raw: "OK\r>", command: "ATL0"))
        XCTAssertThrowsError(try ELM327ResponseParser.expectOK(raw: "\r>", command: "ATL0"))
    }

    func testAdapterVoltage() throws {
        XCTAssertEqual(try ELM327ResponseParser.adapterVoltage(raw: "12.6V\r\r>"), 12.6, accuracy: 0.001)
        XCTAssertEqual(try ELM327ResponseParser.adapterVoltage(raw: "ATRV\r14.2V\r>"), 14.2, accuracy: 0.001)
        XCTAssertThrowsError(try ELM327ResponseParser.adapterVoltage(raw: "?\r>"))
    }
}
