#!/usr/bin/env bash
# 在沒有 Apple SDK 的 Linux 上，用假的 CoreBluetooth 模組對 SagitarCore（含 BLEOBDTransport.swift）做型別檢查。
# 這只能抓出語法 / 型別錯誤，不代表在真的 iOS 上可以正確運作。
set -euo pipefail
cd "$(dirname "$0")"
OUT=$(mktemp -d)
swiftc -emit-module -parse-as-library -module-name CoreBluetooth typecheck-stubs/CoreBluetoothStub.swift -emit-module-path "$OUT/CoreBluetooth.swiftmodule"
swiftc -typecheck -parse-as-library -module-name SagitarCore -I "$OUT" $(find ../SagitarCore/Sources -name '*.swift')
echo "typecheck OK (SagitarCore + BLEOBDTransport against CoreBluetooth stub)"
