import Foundation

/// 單一 ECU 的 Mode 01 回應。
public struct ECUResponse: Equatable, Sendable {
    /// CAN 標頭（例如 "7E8"）；ATH0 時通常為 nil
    public var header: String?
    /// 去掉 0x41 與 PID 之後的資料位元組
    public var data: [UInt8]

    public init(header: String? = nil, data: [UInt8]) {
        self.header = header
        self.data = data
    }
}

/// ELM327 回應解析器（純函式、無狀態，方便單元測試）。
///
/// 能容忍：
/// - 有空白或無空白（ATS0/ATS1）
/// - 回顯（ATE1 時第一行是指令本身）
/// - "SEARCHING..."、"BUS INIT: ...OK" 等協定搜尋訊息
/// - 多個 ECU 各回一行（優先採用引擎 ECU 7E8，否則取第一個）
/// - ISO-TP 多訊框格式（"00A" 長度行 + "0:"、"1:" 分段）
/// - 開啟標頭時的 11-bit CAN 標頭與 PCI 位元組
/// - 錯誤字串："NO DATA"、"UNABLE TO CONNECT"、"?"、"STOPPED"、"BUS INIT: ...ERROR"、"CAN ERROR" 等
public enum ELM327ResponseParser {

    // MARK: - 行切割與清理

    /// 把原始回應切成有意義的行：去掉 '>'、NUL、回顯、"SEARCHING..."、"BUS INIT: ...OK"。
    public static func meaningfulLines(from raw: String, command: String? = nil) -> [String] {
        let normalizedCommand = command.map(OBDCommandWhitelist.normalize)
        let cleaned = raw
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: ">", with: "")
        var result: [String] = []
        for piece in cleaned.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
            var line = piece.trimmingCharacters(in: .whitespaces).uppercased()
            if line.isEmpty { continue }

            // 協定搜尋訊息
            if line.hasPrefix("SEARCHING") {
                line = String(line.dropFirst("SEARCHING".count)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                if line.isEmpty { continue }
            }
            if line.hasPrefix("BUS INIT") && !line.contains("ERROR") {
                var rest = String(line.dropFirst("BUS INIT".count))
                rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: ":. "))
                if rest.hasPrefix("OK") { rest = String(rest.dropFirst(2)) }
                line = rest.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
            }

            // 回顯
            if let normalizedCommand {
                let compact = line.filter { !$0.isWhitespace }
                if compact == normalizedCommand { continue }
                // 回顯與資料黏在同一行（少數仿製品）："010C410C1AF8"
                if normalizedCommand.hasPrefix("01"), compact.hasPrefix(normalizedCommand),
                   compact.count > normalizedCommand.count {
                    line = String(compact.dropFirst(normalizedCommand.count))
                }
            }
            result.append(line)
        }
        return result
    }

    // MARK: - 錯誤辨識

    /// 若這一行是 ELM327 錯誤訊息，回傳對應錯誤。
    public static func error(forLine line: String) -> ELM327Error? {
        let l = line.trimmingCharacters(in: .whitespaces).uppercased()
        switch l {
        case "NO DATA": return .noData
        case "UNABLE TO CONNECT": return .unableToConnect
        case "?": return .unknownCommand
        case "STOPPED": return .stopped
        case "BUFFER FULL": return .bufferFull
        case "BUS ERROR", "CAN ERROR", "BUS BUSY", "FB ERROR": return .busError(l)
        case "ERROR", "DATA ERROR", "ACT ALERT", "LV RESET", "LP ALERT": return .adapterError(l)
        default: break
        }
        if l.hasPrefix("BUS INIT") && l.contains("ERROR") { return .busError(l) }
        if l.contains("RX ERROR") || l.contains("<DATA ERROR") { return .adapterError(l) }
        if l.hasPrefix("ERR") && l.count <= 5 { return .adapterError(l) } // 例如 "ERR94"
        return nil
    }

    /// 回應中第一個錯誤（若有）。
    public static func firstError(in lines: [String]) -> ELM327Error? {
        for line in lines { if let e = error(forLine: line) { return e } }
        return nil
    }

    // MARK: - 十六進位

    /// 一行十六進位字串轉為位元組；含非十六進位字元則回傳 nil。
    /// 若去空白後長度為奇數，前 3 個字元視為 11-bit CAN 標頭。
    static func hexBytes(_ line: String) -> (header: String?, bytes: [UInt8])? {
        let tokens = line.split(separator: " ").map(String.init)
        var compact = tokens.joined()
        guard !compact.isEmpty, compact.allSatisfy(\.isHexDigit) else { return nil }
        var header: String?
        if compact.count % 2 == 1 {
            guard compact.count >= 3 else { return nil }
            header = String(compact.prefix(3))
            compact = String(compact.dropFirst(3))
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(compact.count / 2)
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let b = UInt8(compact[index..<next], radix: 16) else { return nil }
            bytes.append(b)
            index = next
        }
        return (header, bytes)
    }

    // MARK: - 多訊框合併

    /// 把 ISO-TP 多訊框（"0:"、"1:"…）合併成單一訊息；其他行原樣保留。
    static func mergeMultiFrame(_ lines: [String]) -> [String] {
        var output: [String] = []
        var current: String?
        var expectedLength: Int?
        var pendingLengthLine: String?

        func flush() {
            if let c = current {
                var merged = c
                if let len = expectedLength, merged.count > len * 2 {
                    merged = String(merged.prefix(len * 2))
                }
                output.append(merged)
            }
            current = nil
            expectedLength = nil
        }

        for line in lines {
            let compact = line.filter { !$0.isWhitespace }
            if let colon = compact.firstIndex(of: ":"),
               compact.distance(from: compact.startIndex, to: colon) == 1,
               compact.first?.isHexDigit == true {
                let frameIndex = compact.first!
                let payload = String(compact[compact.index(after: colon)...])
                if frameIndex == "0" {
                    flush()
                    current = payload
                    if let p = pendingLengthLine { expectedLength = Int(p, radix: 16) }
                    pendingLengthLine = nil
                } else {
                    current = (current ?? "") + payload
                }
                continue
            }
            // 3 個十六進位字元的單獨一行 = 多訊框的總長度
            if compact.count == 3, compact.allSatisfy(\.isHexDigit) {
                flush()
                if let p = pendingLengthLine { output.append(p) }
                pendingLengthLine = compact
                continue
            }
            flush()
            if let p = pendingLengthLine { output.append(p); pendingLengthLine = nil }
            output.append(line)
        }
        flush()
        if let p = pendingLengthLine { output.append(p) }
        return output
    }

    // MARK: - Mode 01

    /// 解析 Mode 01 回應，回傳所有 ECU 的資料。
    public static func ecuResponses(raw: String, pid: UInt8, command: String? = nil) throws -> [ECUResponse] {
        let cmd = command ?? String(format: "01%02X", pid)
        let lines = mergeMultiFrame(meaningfulLines(from: raw, command: cmd))
        var responses: [ECUResponse] = []
        for line in lines {
            if error(forLine: line) != nil { continue }
            guard let (header, bytes) = hexBytes(line) else { continue }
            // 在位元組中找 0x41 PID（可容忍前面有 PCI 位元組）
            guard bytes.count >= 2 else { continue }
            var found: Int?
            for i in 0..<(bytes.count - 1) where bytes[i] == 0x41 && bytes[i + 1] == pid {
                found = i
                break
            }
            guard let start = found else { continue }
            let data = Array(bytes[(start + 2)...])
            guard !data.isEmpty else { continue }
            responses.append(ECUResponse(header: header, data: data))
        }
        if responses.isEmpty {
            if let e = firstError(in: lines) { throw e }
            throw ELM327Error.malformedResponse(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return responses
    }

    /// 解析 Mode 01 回應並回傳「首選 ECU」的資料位元組（7E8 引擎 ECU 優先）。
    public static func mode01Data(raw: String, pid: UInt8, minimumBytes: Int = 1) throws -> [UInt8] {
        let all = try ecuResponses(raw: raw, pid: pid)
        let usable = all.filter { $0.data.count >= minimumBytes }
        guard !usable.isEmpty else {
            throw ELM327Error.malformedResponse("位元組不足 / not enough bytes: \(raw)")
        }
        if let engine = usable.first(where: { $0.header == "7E8" }) { return engine.data }
        return usable[0].data
    }

    /// 解析並換算成工程單位。
    public static func value(for pid: OBDPID, raw: String) throws -> Double {
        let data = try mode01Data(raw: raw, pid: pid.rawValue, minimumBytes: pid.dataByteCount)
        guard let v = pid.decode(data) else {
            throw ELM327Error.malformedResponse(raw)
        }
        return v
    }

    /// 解析「支援的 PID」位元遮罩；多個 ECU 時取聯集。
    public static func supportedPIDs(raw: String, base: UInt8) throws -> Set<UInt8> {
        let all = try ecuResponses(raw: raw, pid: base)
        return all.reduce(into: Set<UInt8>()) { set, r in
            set.formUnion(OBDFormulas.supportedPIDs(base: base, bitmask: r.data))
        }
    }

    // MARK: - AT 指令

    /// AT 指令的一般回應：有錯誤就丟出，否則回傳清理後的各行。
    @discardableResult
    public static func atResponse(raw: String, command: String) throws -> [String] {
        let lines = meaningfulLines(from: raw, command: command)
        if let e = firstError(in: lines) { throw e }
        return lines
    }

    /// 期待 "OK" 的 AT 指令。
    public static func expectOK(raw: String, command: String) throws {
        let lines = try atResponse(raw: raw, command: command)
        guard lines.contains(where: { $0.contains("OK") }) else {
            throw ELM327Error.malformedResponse(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// 解析 ATRV 的電壓，例如 "12.6V"。
    public static func adapterVoltage(raw: String) throws -> Double {
        let lines = try atResponse(raw: raw, command: "ATRV")
        for line in lines {
            let numeric = line.replacingOccurrences(of: "V", with: "").trimmingCharacters(in: .whitespaces)
            if let v = Double(numeric) { return v }
        }
        throw ELM327Error.malformedResponse(raw)
    }
}
