import Foundation

/// 唯讀指令白名單。
///
/// 安全原則：這個 App **只讀不寫**。任何會改變 ECU 狀態或在 CAN 匯流排上送出自訂訊框的指令
/// （例如 Mode 04 清除故障碼、Mode 08 控制、AT SH 設定標頭後送自訂資料、AT MA 監聽等）
/// 一律拒絕。採「白名單」而非「黑名單」，未列出的一律不准送。
public enum OBDCommandWhitelist {
    /// 允許的 AT 指令（皆只影響 ELM327 轉接器本身的設定，不會送資料到車上）。
    public static let allowedATCommands: Set<String> = [
        "ATZ",    // 重置轉接器
        "ATWS",   // 暖重置
        "ATE0",   // 關閉回顯
        "ATL0",   // 關閉換行
        "ATS0",   // 關閉空白
        "ATH0",   // 關閉標頭
        "ATSP0",  // 自動搜尋協定
        "ATI",    // 轉接器版本
        "ATRV",   // 讀取轉接器量到的電壓（OBD 腳位 16）
        "ATDP",   // 目前協定名稱
        "ATDPN",  // 目前協定代碼
        "ATAT1",  // 自適應逾時
        "ATPC",   // 關閉協定
    ]

    /// 允許的 Mode 01（讀取即時資料）PID。
    public static let allowedMode01PIDs: Set<UInt8> = Set(OBDPID.allCases.map(\.rawValue))

    /// 正規化：去空白、轉大寫、去掉結尾的 CR/LF。
    public static func normalize(_ command: String) -> String {
        command
            .uppercased()
            .filter { !$0.isWhitespace }
    }

    /// 這個指令是否允許送出？
    public static func isAllowed(_ command: String) -> Bool {
        // 原始字串中若夾帶 CR/LF 等控制字元（可能一次塞多條指令），直接拒絕。
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return false
        }
        let cmd = normalize(command)
        guard !cmd.isEmpty, cmd.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return false
        }
        if cmd.hasPrefix("AT") {
            return allowedATCommands.contains(cmd)
        }
        // Mode 01：剛好 4 個十六進位字元 "01XX"
        if cmd.count == 4, cmd.hasPrefix("01"), let pid = UInt8(cmd.dropFirst(2), radix: 16) {
            return allowedMode01PIDs.contains(pid)
        }
        return false
    }
}
