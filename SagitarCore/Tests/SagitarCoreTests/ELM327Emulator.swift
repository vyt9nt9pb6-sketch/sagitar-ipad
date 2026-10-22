import Foundation
@testable import SagitarCore

/// 測試用的 ELM327 行為模擬：記住 ATE/ATS/ATH 狀態，依設定回傳 PID 資料。
final class ELM327Emulator: @unchecked Sendable {
    private let lock = NSLock()
    var echo = true
    var spaces = true
    var headers = false
    var vehicleConnected = true
    var searched = false
    /// PID → 資料位元組（不含 41 PID）
    var values: [UInt8: [UInt8]] = [
        0x0C: [0x1A, 0xF8],       // 1726 rpm
        0x0D: [0x3C],             // 60 km/h
        0x05: [0x7B],             // 83 °C
        0x42: [0x37, 0x6E],       // 14.190 V
        0x2F: [0x80],             // 50.2 %
        0x10: [0x03, 0xE8],       // 10.00 g/s
        0x0B: [0x50],             // 80 kPa
        0x0F: [0x41],             // 25 °C
    ]
    /// 0100 / 0120 / 0140 的遮罩
    var bitmasks: [UInt8: [UInt8]] = [
        0x00: [0x98, 0x3B, 0xA0, 0x13],  // 01,04,05,0B,0C,0D,0F,10,11,13,1C,1F,20
        0x20: [0x80, 0x02, 0x00, 0x01],  // 21,2F,40
        0x40: [0x40, 0x00, 0x00, 0x00],  // 42
    ]
    var voltageText = "12.6V"
    var stopNext = false

    func set(_ body: (ELM327Emulator) -> Void) {
        lock.lock(); body(self); lock.unlock()
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: spaces ? " " : "")
    }

    func respond(_ raw: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        let cmd = raw.uppercased().filter { !$0.isWhitespace }
        let prefix = echo ? raw + "\r" : ""
        func reply(_ body: String) -> String { prefix + body }

        switch cmd {
        case "ATZ":
            echo = true; spaces = true; headers = false; searched = false
            return raw + "\r\r\rELM327 v1.5"
        case "ATE0": defer { echo = false }; return reply("OK")
        case "ATE1": echo = true; return reply("OK")
        case "ATL0": return reply("OK")
        case "ATS0": defer { spaces = false }; return reply("OK")
        case "ATH0": headers = false; return reply("OK")
        case "ATSP0": searched = false; return reply("OK")
        case "ATDP": return reply("AUTO, ISO 15765-4 (CAN 11/500)")
        case "ATRV": return reply(voltageText)
        default: break
        }
        guard cmd.count == 4, cmd.hasPrefix("01"), let pid = UInt8(cmd.dropFirst(2), radix: 16) else {
            return reply("?")
        }
        var lead = ""
        if !searched {
            lead = "SEARCHING...\r"
            searched = vehicleConnected
        }
        guard vehicleConnected else { return reply(lead + "UNABLE TO CONNECT") }
        if stopNext { stopNext = false; return reply("STOPPED") }
        let data = bitmasks[pid] ?? values[pid]
        guard let data else { return reply(lead + "NO DATA") }
        let frame = hex([0x41, pid] + data)
        let header = headers ? (spaces ? "7E8 \(String(format: "%02X", data.count + 2)) " : "7E8\(String(format: "%02X", data.count + 2))") : ""
        return reply(lead + header + frame)
    }

    func makeTransport(chunkSize: Int = 0) -> MockOBDTransport {
        MockOBDTransport(chunkSize: chunkSize) { [self] cmd in self.respond(cmd) }
    }
}
