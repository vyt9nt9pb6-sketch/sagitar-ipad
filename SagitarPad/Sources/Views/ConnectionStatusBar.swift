import SwiftUI
import SagitarCore

/// 上方狀態列：連線狀態、時鐘、資料來源選單、重新連線、設定。
struct ConnectionStatusBar: View {
    var state: ConnectionState
    var sourceKind: DataSourceKind
    var onSelectSource: (DataSourceKind) -> Void
    var onReconnect: () -> Void
    var onSettings: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .shadow(color: color.opacity(0.8), radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey("state.\(state.code)"))
                    .font(.system(size: 20, weight: .semibold))
                if let detail = state.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer()

            Menu {
                Picker("source.title", selection: Binding(get: { sourceKind }, set: onSelectSource)) {
                    ForEach(DataSourceKind.allCases) { kind in
                        Label(LocalizedStringKey("source.\(kind.rawValue)"), systemImage: DataSourceKind.icon(kind))
                            .tag(kind)
                    }
                }
            } label: {
                Label(LocalizedStringKey("source.\(sourceKind.rawValue)"), systemImage: DataSourceKind.icon(sourceKind))
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Button(action: onReconnect) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 56, height: 52)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .accessibilityLabel(Text("action.reconnect"))

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 56, height: 52)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .accessibilityLabel(Text("settings.title"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var color: Color {
        switch state {
        case .connected: return Theme.ok
        case .scanning, .connecting, .initializing: return Theme.warning
        case .vehicleNotResponding: return Theme.warning
        case .failed, .unavailable: return Theme.danger
        case .disconnected: return Theme.secondaryText
        }
    }
}

extension DataSourceKind {
    static func icon(_ kind: DataSourceKind) -> String {
        switch kind {
        case .simulator: return "play.circle"
        case .bleOBD: return "antenna.radiowaves.left.and.right"
        case .exlap: return "car.side"
        }
    }
}
