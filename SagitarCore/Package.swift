// swift-tools-version:5.9
// SagitarCore：與平台無關的核心程式庫（OBD-II / ELM327 協定、解析、資料來源、模擬器、行車電腦）。
// 在 Linux 上可直接 `swift test`；CoreBluetooth 相關程式碼以 `#if canImport(CoreBluetooth)` 隔離。
import PackageDescription

let package = Package(
    name: "SagitarCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SagitarCore", targets: ["SagitarCore"]),
    ],
    targets: [
        .target(name: "SagitarCore"),
        .testTarget(name: "SagitarCoreTests", dependencies: ["SagitarCore"]),
    ]
)
