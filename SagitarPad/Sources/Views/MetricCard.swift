import SwiftUI

/// 單一數值卡片：標題、圖示、大數字、單位、可選的副標與顏色。
struct MetricCard: View {
    var title: LocalizedStringKey
    var systemImage: String
    var value: String
    var unit: LocalizedStringKey
    var subtitle: Text? = nil
    var tint: Color = .white
    /// 0…1 的進度條（例如油量）；nil 不顯示
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: value)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            if let progress {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(tint)
                            .frame(width: g.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 10)
            }
            if let subtitle {
                subtitle
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
