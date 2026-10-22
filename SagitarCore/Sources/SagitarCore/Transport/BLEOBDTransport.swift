#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

/// 常見 BLE ELM327 轉接器的 GATT 服務 / 特徵值 UUID。
public struct BLEOBDProfile: Sendable, Equatable {
    public var service: String
    /// 用來收資料（notify / indicate）
    public var notify: String
    /// 用來寫指令（write / writeWithoutResponse）
    public var write: String

    public init(service: String, notify: String, write: String) {
        self.service = service
        self.notify = notify
        self.write = write
    }

    /// 已知組合（依常見程度排列）：
    /// - FFE0 / FFE1：HM-10 類晶片，同一個特徵值兼讀寫（許多便宜的「iOS 相容」ELM327）
    /// - FFF0 / FFF1 / FFF2：FFF1 通知、FFF2 寫入
    /// - 18F0 / 2AF0 / 2AF1：2AF0 通知、2AF1 寫入
    /// - Vgate iCar Pro BLE 等使用的自訂 128-bit UUID
    public static let known: [BLEOBDProfile] = [
        BLEOBDProfile(service: "FFE0", notify: "FFE1", write: "FFE1"),
        BLEOBDProfile(service: "FFF0", notify: "FFF1", write: "FFF2"),
        BLEOBDProfile(service: "18F0", notify: "2AF0", write: "2AF1"),
        BLEOBDProfile(service: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2",
                      notify: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F",
                      write: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F"),
    ]
}

/// CoreBluetooth 傳輸層：掃描、連線、找到讀寫特徵值，並把收到的位元組交給 `ELM327Session`。
/// 所有 CoreBluetooth 狀態都在專用的序列佇列上存取。
public final class BLEOBDTransport: NSObject, OBDTransport, @unchecked Sendable {
    public struct Options: Sendable {
        /// 掃描逾時（秒）
        public var scanTimeout: TimeInterval
        /// 指定要連的裝置（上次連過的），nil 則連第一個符合的
        public var preferredPeripheral: UUID?
        /// 有些轉接器不在廣播中宣告服務 UUID；開啟後會掃描所有裝置並以名稱過濾
        public var scanAllDevices: Bool
        /// 名稱關鍵字（scanAllDevices 時使用）
        public var nameKeywords: [String]

        public init(scanTimeout: TimeInterval = 12,
                    preferredPeripheral: UUID? = nil,
                    scanAllDevices: Bool = true,
                    nameKeywords: [String] = ["OBD", "ELM", "VLINK", "V-LINK", "VGATE", "ICAR", "KONNWEI", "VEEPEAK", "CARISTA", "IOS-VLINK", "OBDII", "OBD2"]) {
            self.scanTimeout = scanTimeout
            self.preferredPeripheral = preferredPeripheral
            self.scanAllDevices = scanAllDevices
            self.nameKeywords = nameKeywords
        }
    }

    private let queue = DispatchQueue(label: "com.kwok.sagitarpad.ble")
    private var central: CBCentralManager!
    private let options: Options
    private let profiles: [BLEOBDProfile]

    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withResponse

    private var poweredOnWaiters: [CheckedContinuation<Void, Error>] = []
    private var connectContinuation: CheckedContinuation<String, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var incoming: AsyncStream<Data>.Continuation?
    private var scanTimer: DispatchWorkItem?

    /// 最後連上的裝置識別碼（App 可存到 UserDefaults）
    public private(set) var connectedPeripheralID: UUID?

    public init(options: Options = .init(), profiles: [BLEOBDProfile] = BLEOBDProfile.known) {
        self.options = options
        self.profiles = profiles
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    private var serviceUUIDs: [CBUUID] { profiles.map { CBUUID(string: $0.service) } }

    // MARK: OBDTransport

    public func incomingBytes() -> AsyncStream<Data> {
        AsyncStream { continuation in
            queue.async { self.incoming = continuation }
        }
    }

    public func connect() async throws -> String {
        try await waitForPoweredOn()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            queue.async {
                self.connectContinuation = c
                // 先試上次連過的裝置
                if let id = self.options.preferredPeripheral,
                   let known = self.central.retrievePeripherals(withIdentifiers: [id]).first {
                    self.connectTo(known)
                    return
                }
                // 已被系統連上（例如其他 App）的裝置
                if let connected = self.central.retrieveConnectedPeripherals(withServices: self.serviceUUIDs).first {
                    self.connectTo(connected)
                    return
                }
                self.central.scanForPeripherals(
                    withServices: self.options.scanAllDevices ? nil : self.serviceUUIDs,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
                let timer = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.central.stopScan()
                    self.finishConnect(.failure(ELM327Error.transport("BLE scan timeout: no OBD adapter found")))
                }
                self.scanTimer = timer
                self.queue.asyncAfter(deadline: .now() + self.options.scanTimeout, execute: timer)
            }
        }
    }

    public func disconnect() async {
        queue.sync {
            scanTimer?.cancel()
            central.stopScan()
            if let p = peripheral { central.cancelPeripheralConnection(p) }
            peripheral = nil
            writeCharacteristic = nil
            notifyCharacteristic = nil
            incoming?.finish()
            incoming = nil
            finishConnect(.failure(ELM327Error.notConnected))
            if let w = writeContinuation {
                writeContinuation = nil
                w.resume(throwing: ELM327Error.notConnected)
            }
        }
    }

    public func send(_ data: Data) async throws {
        let (p, ch, type): (CBPeripheral?, CBCharacteristic?, CBCharacteristicWriteType) = queue.sync {
            (peripheral, writeCharacteristic, writeType)
        }
        guard let p, let ch else { throw ELM327Error.notConnected }
        let chunkSize = max(20, p.maximumWriteValueLength(for: type))
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            if type == .withResponse {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    queue.async {
                        self.writeContinuation = c
                        p.writeValue(chunk, for: ch, type: .withResponse)
                    }
                }
            } else {
                queue.sync { p.writeValue(chunk, for: ch, type: .withoutResponse) }
            }
            offset = end
        }
    }

    // MARK: 內部

    private func waitForPoweredOn() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async {
                switch self.central.state {
                case .poweredOn: c.resume()
                case .unauthorized: c.resume(throwing: ELM327Error.transport("Bluetooth permission denied"))
                case .unsupported: c.resume(throwing: ELM327Error.transport("Bluetooth LE unsupported"))
                case .poweredOff: c.resume(throwing: ELM327Error.transport("Bluetooth is off"))
                default: self.poweredOnWaiters.append(c) // unknown / resetting：等狀態更新
                }
            }
        }
    }

    private func connectTo(_ p: CBPeripheral) {
        scanTimer?.cancel()
        central.stopScan()
        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    private func finishConnect(_ result: Result<String, Error>) {
        guard let c = connectContinuation else { return }
        connectContinuation = nil
        c.resume(with: result)
    }

    private func matches(name: String?, advertisement: [String: Any]) -> Bool {
        if let uuids = advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           uuids.contains(where: { serviceUUIDs.contains($0) }) {
            return true
        }
        guard let name = name?.uppercased() else { return false }
        return options.nameKeywords.contains { name.contains($0) }
    }
}

extension BLEOBDTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let waiters = poweredOnWaiters
        switch central.state {
        case .poweredOn:
            poweredOnWaiters.removeAll()
            waiters.forEach { $0.resume() }
        case .unauthorized, .unsupported, .poweredOff:
            poweredOnWaiters.removeAll()
            waiters.forEach { $0.resume(throwing: ELM327Error.transport("Bluetooth unavailable (\(central.state.rawValue))")) }
            if peripheral != nil {
                incoming?.finish()
                incoming = nil
            }
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil, connectContinuation != nil else { return }
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard matches(name: name, advertisement: advertisementData) else { return }
        connectTo(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // 找服務；若轉接器不在已知清單中，探索全部服務
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        finishConnect(.failure(ELM327Error.transport("BLE connect failed: \(error?.localizedDescription ?? "unknown")")))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        finishConnect(.failure(ELM327Error.transport("BLE disconnected")))
        incoming?.finish()
        incoming = nil
    }
}

extension BLEOBDTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            finishConnect(.failure(ELM327Error.transport("Service discovery failed: \(error.localizedDescription)")))
            return
        }
        let services = peripheral.services ?? []
        let known = services.filter { serviceUUIDs.contains($0.uuid) }
        guard !known.isEmpty else {
            central.cancelPeripheralConnection(peripheral)
            finishConnect(.failure(ELM327Error.transport("No known OBD service on \(peripheral.name ?? "device")")))
            return
        }
        for s in known { peripheral.discoverCharacteristics(nil, for: s) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard writeCharacteristic == nil,
              let profile = profiles.first(where: { CBUUID(string: $0.service) == service.uuid }),
              let chars = service.characteristics else { return }
        let notify = chars.first { $0.uuid == CBUUID(string: profile.notify) }
            ?? chars.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
        let write = chars.first { $0.uuid == CBUUID(string: profile.write) }
            ?? chars.first { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
        guard let notify, let write else { return }
        notifyCharacteristic = notify
        writeCharacteristic = write
        writeType = write.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.setNotifyValue(true, for: notify)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == notifyCharacteristic?.uuid else { return }
        if let error {
            finishConnect(.failure(ELM327Error.transport("Enable notify failed: \(error.localizedDescription)")))
            return
        }
        connectedPeripheralID = peripheral.identifier
        finishConnect(.success(peripheral.name ?? "ELM327 BLE"))
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == notifyCharacteristic?.uuid, let value = characteristic.value else { return }
        incoming?.yield(value)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let c = writeContinuation else { return }
        writeContinuation = nil
        if let error {
            c.resume(throwing: ELM327Error.transport("Write failed: \(error.localizedDescription)"))
        } else {
            c.resume()
        }
    }
}

/// iPad 上實際使用的 BLE OBD 資料來源：`ELM327DataSource` + `BLEOBDTransport`。
public enum ELM327BLEDataSource {
    public static func make(configuration: ELM327DataSource.Configuration = .init(),
                            options: BLEOBDTransport.Options = .init()) -> ELM327DataSource {
        ELM327DataSource(kind: .bleOBD, configuration: configuration) {
            BLEOBDTransport(options: options)
        }
    }
}
#endif
