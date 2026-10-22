// 只用於在 Linux 上做「型別檢查」的 CoreBluetooth 假模組（API 形狀仿照 Apple SDK，無實作）。
// 不會被打包進 App。用法見 tools/typecheck-ble.sh。
import Foundation

public enum CBManagerState: Int { case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }
open class CBManager: NSObject { open var state: CBManagerState { .unknown } }
public let CBCentralManagerScanOptionAllowDuplicatesKey = "kCBScanOptionAllowDuplicates"
public let CBAdvertisementDataServiceUUIDsKey = "kCBAdvDataServiceUUIDs"
public let CBAdvertisementDataLocalNameKey = "kCBAdvDataLocalName"

open class CBUUID: NSObject { public init(string: String) {} }
open class CBPeer: NSObject { open var identifier: UUID { UUID() } }
open class CBAttribute: NSObject { open var uuid: CBUUID { CBUUID(string: "0000") } }
public struct CBCharacteristicProperties: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let writeWithoutResponse = CBCharacteristicProperties(rawValue: 4)
    public static let write = CBCharacteristicProperties(rawValue: 8)
    public static let notify = CBCharacteristicProperties(rawValue: 16)
    public static let indicate = CBCharacteristicProperties(rawValue: 32)
}
public enum CBCharacteristicWriteType: Int { case withResponse, withoutResponse }
open class CBCharacteristic: CBAttribute {
    open var properties: CBCharacteristicProperties { [] }
    open var value: Data? { nil }
}
open class CBService: CBAttribute { open var characteristics: [CBCharacteristic]? { nil } }

public protocol CBPeripheralDelegate: NSObjectProtocol {}
open class CBPeripheral: CBPeer {
    open var name: String? { nil }
    open weak var delegate: CBPeripheralDelegate?
    open var services: [CBService]? { nil }
    open func discoverServices(_ serviceUUIDs: [CBUUID]?) {}
    open func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {}
    open func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {}
    open func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {}
    open func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int { 20 }
}

public protocol CBCentralManagerDelegate: NSObjectProtocol {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
}
open class CBCentralManager: CBManager {
    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?) {}
    open func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {}
    open func stopScan() {}
    open func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) {}
    open func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
    open func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] { [] }
    open func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [CBPeripheral] { [] }
}
