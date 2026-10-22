import SwiftUI

/// 捷徑：用 URL scheme 開啟系統 App。依序嘗試，第一個成功就停止。
/// 使用 SwiftUI 的 `OpenURLAction`，失敗時會回報 false，因此不需要 LSApplicationQueriesSchemes。
enum ShortcutLauncher {
    static let musicURLs = ["music://", "applemusic://"]
    static let mapsURLs = ["maps://", "https://maps.apple.com/"]

    /// 電話：iPad 沒有行動網路，`tel:` 通常會轉交給 iPhone（接續互通）或 FaceTime；
    /// 不行就改用 FaceTime 語音 / FaceTime。
    static func phoneURLs(number: String) -> [String] {
        let digits = number.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return ["facetime://", "facetime-audio://"] }
        return ["tel:\(digits)", "facetime-audio:\(digits)", "facetime:\(digits)"]
    }

    @MainActor
    static func open(_ candidates: [String], with openURL: OpenURLAction, onAllFailed: @escaping @MainActor () -> Void = {}) {
        open(urls: candidates.compactMap(URL.init(string:)), with: openURL, onAllFailed: onAllFailed)
    }

    @MainActor
    private static func open(urls: [URL], with openURL: OpenURLAction, onAllFailed: @escaping @MainActor () -> Void) {
        guard let first = urls.first else {
            onAllFailed()
            return
        }
        let rest = Array(urls.dropFirst())
        openURL(first) { accepted in
            guard !accepted else { return }
            Task { @MainActor in
                open(urls: rest, with: openURL, onAllFailed: onAllFailed)
            }
        }
    }
}
