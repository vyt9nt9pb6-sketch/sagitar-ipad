import SwiftUI

/// 轉速錶：270° 圓弧，每 1000 rpm 一個刻度，6000 以上紅區，中央顯示車速與轉速。
struct RPMGaugeView: View {
    var rpm: Double?
    var speedKmh: Double?
    var maxRPM: Double = 7000
    var redline: Double = 6000

    private let startAngle = 135.0
    private let sweep = 270.0

    private func angle(for value: Double) -> Angle {
        .degrees(startAngle + sweep * min(max(value / maxRPM, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lineWidth = size * 0.06
            ZStack {
                // 底圈
                ArcShape(start: .degrees(startAngle), end: .degrees(startAngle + sweep))
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // 紅區
                ArcShape(start: angle(for: redline), end: .degrees(startAngle + sweep))
                    .stroke(Theme.danger.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                // 目前轉速
                ArcShape(start: .degrees(startAngle), end: angle(for: rpm ?? 0))
                    .stroke(
                        AngularGradient(colors: [Theme.accentDim, Theme.accent, (rpm ?? 0) >= redline ? Theme.danger : Theme.accent],
                                        center: .center,
                                        startAngle: .degrees(startAngle),
                                        endAngle: .degrees(startAngle + sweep)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .animation(.easeOut(duration: 0.25), value: rpm ?? 0)

                // 刻度與數字
                ForEach(0...Int(maxRPM / 1000), id: \.self) { i in
                    let value = Double(i) * 1000
                    let a = angle(for: value).radians
                    let r = size / 2 - lineWidth * 2.1
                    Text(verbatim: "\(i)")
                        .font(.system(size: size * 0.055, weight: .semibold, design: .rounded))
                        .foregroundStyle(value >= redline ? Theme.danger : Theme.secondaryText)
                        .position(x: geo.size.width / 2 + cos(a) * r,
                                  y: geo.size.height / 2 + sin(a) * r)
                }

                // 中央：車速 + 轉速
                VStack(spacing: size * 0.01) {
                    Text(Fmt.number(speedKmh))
                        .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("unit.kmh")
                        .font(.system(size: size * 0.05, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Text(verbatim: "\(Fmt.number(rpm)) rpm")
                        .font(.system(size: size * 0.065, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle((rpm ?? 0) >= redline ? Theme.danger : Theme.accent)
                        .padding(.top, size * 0.02)
                    Text("gauge.rpm.x1000")
                        .font(.system(size: size * 0.04))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("card.rpm"))
        .accessibilityValue(Text("\(Fmt.number(rpm)) rpm, \(Fmt.number(speedKmh)) km/h"))
    }
}

/// 以中心為圓心的圓弧（角度：0° 指向右，順時針為正，SwiftUI 座標系）。
struct ArcShape: Shape {
    var start: Angle
    var end: Angle

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start.degrees, end.degrees) }
        set { start = .degrees(newValue.first); end = .degrees(newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2 * 0.94
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                 startAngle: start, endAngle: .degrees(max(end.degrees, start.degrees)), clockwise: false)
        return p
    }
}
