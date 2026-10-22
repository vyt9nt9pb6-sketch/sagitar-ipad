import SwiftUI

/// 車機風格深色主題。
enum Theme {
    static let background = Color(red: 0.03, green: 0.04, blue: 0.06)
    static let card = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let cardBorder = Color.white.opacity(0.06)
    static let accent = Color(red: 0.20, green: 0.75, blue: 1.00)   // 冷光藍
    static let accentDim = Color(red: 0.10, green: 0.35, blue: 0.50)
    static let warning = Color(red: 1.00, green: 0.70, blue: 0.20)
    static let danger = Color(red: 1.00, green: 0.30, blue: 0.30)
    static let ok = Color(red: 0.30, green: 0.90, blue: 0.50)
    static let secondaryText = Color.white.opacity(0.55)
    static let cornerRadius: CGFloat = 22
    /// 最小觸控目標（Apple 建議 44pt；車用放大）
    static let minTouch: CGFloat = 64
}

/// 數值格式化（缺值顯示「—」）。
enum Fmt {
    static func number(_ v: Double?, digits: Int = 0) -> String {
        guard let v, v.isFinite else { return "—" }
        return v.formatted(.number.precision(.fractionLength(digits)))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
