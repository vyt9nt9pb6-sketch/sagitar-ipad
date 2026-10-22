#!/usr/bin/env python3
"""產生 Localizable.strings（zh-Hant / en），並檢查 Swift 原始碼用到的 key 都有翻譯。"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "SagitarPad" / "Resources"

S = {
 "unit.kmh": ("km/h", "km/h"),
 "unit.km": ("公里", "km"),
 "unit.celsius": ("°C", "°C"),
 "unit.volt": ("V", "V"),
 "unit.l100km": ("L/100km", "L/100km"),
 "unit.lph": ("L/h", "L/h"),
 "unit.liter": ("公升", "L"),
 "gauge.rpm.x1000": ("× 1000 rpm", "× 1000 rpm"),
 "card.rpm": ("引擎轉速", "Engine RPM"),
 "card.coolant": ("水溫", "Coolant"),
 "card.voltage": ("電壓", "Voltage"),
 "card.instantFuel": ("瞬時油耗", "Instant Fuel"),
 "card.instantFuel.avg %@": ("本次平均 %@ L/100km", "Trip avg %@ L/100km"),
 "card.trip": ("行車電腦", "Trip Computer"),
 "trip.reset": ("歸零", "Reset"),
 "trip.reset.confirm": ("要將行車電腦歸零嗎？", "Reset the trip computer?"),
 "trip.distance": ("里程", "Distance"),
 "trip.time": ("行駛時間", "Driving Time"),
 "trip.avgSpeed": ("平均車速", "Avg Speed"),
 "trip.avgConsumption": ("平均油耗", "Avg Consumption"),
 "trip.fuelUsed": ("耗油量（估）", "Fuel Used (est.)"),
 "trip.fuelLevel": ("油量", "Fuel Level"),
 "trip.fuelRemaining %@": ("約剩 %@ 公升", "About %@ L left"),
 "common.cancel": ("取消", "Cancel"),
 "common.ok": ("好", "OK"),
 "common.close": ("關閉", "Close"),
 "common.done": ("完成", "Done"),
 "state.disconnected": ("未連線", "Disconnected"),
 "state.unavailable": ("無法使用", "Unavailable"),
 "state.scanning": ("搜尋 OBD 轉接器中…", "Scanning for OBD adapter…"),
 "state.connecting": ("連線中…", "Connecting…"),
 "state.initializing": ("初始化轉接器中…", "Initializing adapter…"),
 "state.connected": ("已連線", "Connected"),
 "state.vehicleNotResponding": ("車輛沒有回應（請發動或開 ACC）", "Vehicle not responding (turn ignition on)"),
 "state.failed": ("連線失敗，稍後自動重試", "Connection failed, retrying"),
 "source.title": ("資料來源", "Data Source"),
 "source.simulator": ("模擬器", "Simulator"),
 "source.bleOBD": ("BLE OBD", "BLE OBD"),
 "source.exlap": ("Exlap（未實作）", "Exlap (not implemented)"),
 "source.simulator.help": ("不需要車也能展示：模擬市區／郊區行駛。", "Demo without a car: simulated city/suburban driving."),
 "source.bleOBD.help": ("使用藍牙 4.0（BLE）ELM327 轉接器，插在駕駛座下方的 OBD-II 接頭。只讀取，不寫入。", "Uses a Bluetooth 4.0 (BLE) ELM327 adapter in the OBD-II port. Read-only."),
 "source.exlap.help": ("透過 MIB2 主機的 Exlap 介面讀取 VW 專屬資料。尚未實作，僅為預留。", "VW-specific data via the MIB2 head unit's Exlap interface. Placeholder only."),
 "action.reconnect": ("重新連線", "Reconnect"),
 "settings.title": ("設定", "Settings"),
 "settings.section.source": ("資料來源", "Data Source"),
 "settings.bleScanAll": ("掃描所有藍牙裝置（以名稱辨識轉接器）", "Scan all BLE devices (match by name)"),
 "settings.pollInterval %@": ("輪詢間隔：%@ 秒", "Poll interval: %@ s"),
 "settings.section.fuel": ("油耗推估", "Fuel Estimate"),
 "settings.calibration %@": ("校正係數：%@", "Calibration: %@"),
 "settings.displacement": ("引擎排氣量", "Engine Displacement"),
 "settings.tank %lld": ("油箱容量：%lld 公升", "Tank capacity: %lld L"),
 "settings.fuel.footer": ("油耗由進氣量（MAF）推估，與原廠儀表可能有 10–15% 誤差。加滿油後用「實際加油量 ÷ App 耗油量」調整校正係數。", "Fuel use is estimated from mass air flow and may differ 10–15% from the cluster. Calibrate with actual litres refuelled ÷ app estimate."),
 "settings.section.phone": ("電話", "Phone"),
 "settings.favoritePhone": ("常用電話號碼", "Favorite phone number"),
 "settings.section.display": ("顯示", "Display"),
 "settings.keepScreenOn": ("保持螢幕常亮", "Keep screen on"),
 "settings.section.about": ("關於", "About"),
 "about.vehicle": ("適用：2018 Volkswagen Sagitar（PQ 平台、MIB2 Standard）。只使用標準 OBD-II PID。", "For a 2018 VW Sagitar (PQ platform, MIB2 Standard). Standard OBD-II PIDs only."),
 "about.readOnly": ("本 App 只讀取資料，不會寫入或修改任何 ECU / 主機設定。", "This app only reads data; it never writes to any ECU or head unit."),
 "about.safety": ("行車中請勿操作 iPad。請由乘客操作或停車後再使用。", "Do not operate the iPad while driving."),
 "shortcut.media": ("媒體", "Media"),
 "shortcut.navigation": ("導航", "Navigation"),
 "shortcut.phone": ("電話", "Phone"),
 "shortcut.failed.music": ("無法開啟 Apple Music。", "Couldn't open Apple Music."),
 "shortcut.failed.maps": ("無法開啟 Apple 地圖。", "Couldn't open Apple Maps."),
 "shortcut.failed.phone": ("無法撥號：這台 iPad 不支援電話或 FaceTime。", "Can't call: this iPad doesn't support phone calls or FaceTime."),
 "phone.placeholder": ("輸入電話號碼", "Enter phone number"),
 "phone.call": ("撥打", "Call"),
 "phone.facetime": ("開啟 FaceTime", "Open FaceTime"),
 "phone.favorite %@": ("常用：%@", "Favorite: %@"),
 "coolant.cold": ("引擎尚未暖車", "Engine warming up"),
 "coolant.hot": ("水溫過高！請安全停車", "Overheating! Pull over safely"),
 "coolant.normal": ("正常", "Normal"),
 "voltage.charging": ("發電機充電中", "Charging"),
 "voltage.lowCharge": ("充電電壓偏低", "Low charging voltage"),
 "voltage.batteryOK": ("電瓶正常", "Battery OK"),
 "voltage.batteryLow": ("電瓶電壓偏低", "Battery low"),
}

INFOPLIST = {
 "NSBluetoothAlwaysUsageDescription": (
   "需要使用藍牙連接 OBD-II（ELM327 BLE）轉接器，以讀取車速、轉速、水溫等行車資料。本 App 只讀取，不會寫入車輛。",
   "Bluetooth is used to connect to your OBD-II (ELM327 BLE) adapter to read speed, RPM, coolant temperature and other data. The app is read-only and never writes to the vehicle."),
 "CFBundleDisplayName": ("Sagitar 車機", "SagitarPad"),
}

def esc(s): return s.replace("\\", "\\\\").replace('"', '\\"')

def write(lang_idx, folder):
    d = RES / folder
    d.mkdir(parents=True, exist_ok=True)
    with open(d / "Localizable.strings", "w", encoding="utf-8") as f:
        f.write("/* 由 tools/gen_strings.py 產生 */\n")
        for k, v in S.items():
            f.write(f'"{esc(k)}" = "{esc(v[lang_idx])}";\n')
    with open(d / "InfoPlist.strings", "w", encoding="utf-8") as f:
        for k, v in INFOPLIST.items():
            f.write(f'"{k}" = "{esc(v[lang_idx])}";\n')

def used_keys():
    keys = set()
    src = ROOT / "SagitarPad" / "Sources"
    for p in src.rglob("*.swift"):
        t = p.read_text(encoding="utf-8")
        for m in re.finditer(r'(systemImage: |systemName: |label: |return )?"([a-z][A-Za-z]*(?:\.[A-Za-z0-9]+)+)( \\\(.*?\)(?="))?"', t):
            if m.group(1):
                continue  # SF Symbols 名稱 / 佇列名稱，不是在地化 key
            literal = m.group(0)[1:-1]
            if "\\(" in literal:
                # 插值：依型別推測格式
                key = m.group(2) + (" %lld" if "Int(" in literal else " %@")
            else:
                key = literal
            keys.add(key)
    return keys

def dynamic_keys():
    """以字串插值組出的 key（state.*、source.*）。"""
    ks = {f"state.{c}" for c in ["disconnected","unavailable","scanning","connecting","initializing","connected","vehicleNotResponding","failed"]}
    for s in ["simulator","bleOBD","exlap"]:
        ks |= {f"source.{s}", f"source.{s}.help"}
    return ks

if __name__ == "__main__":
    write(0, "zh-Hant.lproj")
    write(1, "en.lproj")
    ignore = {"com.kwok.sagitarpad.ble"}
    needed = (used_keys() | dynamic_keys()) - ignore
    missing = sorted(k for k in needed if k not in S)
    unused = sorted(k for k in S if k not in needed)
    print(f"keys defined: {len(S)}, used: {len(needed)}")
    if unused: print("unused:", unused)
    if missing:
        print("MISSING:", missing); sys.exit(1)
    print("OK: all used keys localized in zh-Hant and en")
