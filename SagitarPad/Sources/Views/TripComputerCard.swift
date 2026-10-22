import SwiftUI
import SagitarCore

/// 行車電腦：里程、時間、平均車速、平均油耗、油量。
struct TripComputerCard: View {
    var trip: TripSummary
    var fuelLevelPercent: Double?
    var tankCapacity: Double
    var onReset: () -> Void
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("card.trip", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button {
                    confirmReset = true
                } label: {
                    Label("trip.reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .confirmationDialog("trip.reset.confirm", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("trip.reset", role: .destructive, action: onReset)
                    Button("common.cancel", role: .cancel) {}
                }
            }

            row("trip.distance", Fmt.number(trip.distanceKm, digits: 1), "unit.km")
            row("trip.time", Fmt.duration(trip.elapsedSeconds), nil)
            row("trip.avgSpeed", Fmt.number(trip.averageSpeedKmh), "unit.kmh")
            row("trip.avgConsumption", Fmt.number(trip.averageLitersPer100km, digits: 1), "unit.l100km")
            row("trip.fuelUsed", Fmt.number(trip.fuelUsedLiters, digits: 2), "unit.liter")

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label("trip.fuelLevel", systemImage: "fuelpump.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text(verbatim: Fmt.number(fuelLevelPercent))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(fuelTint)
                    Text(verbatim: "%")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.secondaryText)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(fuelTint)
                            .frame(width: g.size.width * min(max((fuelLevelPercent ?? 0) / 100, 0), 1))
                    }
                }
                .frame(height: 12)
                if let pct = fuelLevelPercent {
                    Text("trip.fuelRemaining \(Fmt.number(pct / 100 * tankCapacity, digits: 0))")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var fuelTint: Color {
        guard let f = fuelLevelPercent else { return Theme.secondaryText }
        if f < 10 { return Theme.danger }
        if f < 20 { return Theme.warning }
        return Theme.ok
    }

    private func row(_ title: LocalizedStringKey, _ value: String, _ unit: LocalizedStringKey?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(verbatim: value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            if let unit {
                Text(unit)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 70, alignment: .leading)
            } else {
                Color.clear.frame(width: 70, height: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
