import XCTest
@testable import SagitarCore

final class WhitelistTests: XCTestCase {
    func testInitSequenceAllowed() {
        for cmd in ELM327Session.initSequence {
            XCTAssertTrue(OBDCommandWhitelist.isAllowed(cmd), cmd)
        }
    }

    func testPollPIDsAllowed() {
        for cmd in ["010C", "010D", "0105", "0142", "012F", "0110", "0100", "0120", "0140", "010B", "010F"] {
            XCTAssertTrue(OBDCommandWhitelist.isAllowed(cmd), cmd)
        }
    }

    func testNormalizationAllowsSpacesAndLowercase() {
        XCTAssertTrue(OBDCommandWhitelist.isAllowed("at z"))
        XCTAssertTrue(OBDCommandWhitelist.isAllowed("01 0c"))
        XCTAssertTrue(OBDCommandWhitelist.isAllowed("  ATRV "))
    }

    func testWritesAndUnknownCommandsRejected() {
        let rejected = [
            "04",              // 清除故障碼（會寫入 ECU）
            "0400",
            "08",              // Mode 08 控制
            "0801",
            "14FF00",          // UDS 清除 DTC
            "2E F190 00",      // UDS 寫入資料
            "3101FF00",        // UDS routine control
            "1003",            // 診斷工作階段
            "03",              // 讀故障碼：唯讀但不在白名單 → 拒絕（白名單原則）
            "0902",            // VIN：同上
            "AT SH 7E0",       // 設定標頭（之後可送自訂 CAN 訊框）
            "ATCRA7E8",
            "ATMA",            // 監聽全部
            "ATPP 0C SV 23",   // 寫轉接器 EEPROM
            "ATBRD 23",
            "STPX H:7E0, D:01 0C", // STN 晶片自訂訊框
            "01FF",            // 未列入的 PID
            "010",             // 長度不對
            "010C1",
            "",
            "   ",
            "010C\r04",        // 夾帶第二條指令
            "010C\n",
            "ATZ;04",
            "ＡＴＺ",           // 全形字
        ]
        for cmd in rejected {
            XCTAssertFalse(OBDCommandWhitelist.isAllowed(cmd), "should reject: \(cmd.debugDescription)")
        }
    }
}
