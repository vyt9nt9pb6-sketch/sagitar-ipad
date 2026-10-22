import SwiftUI

/// 下方捷徑列：媒體（Apple Music）、導航（Apple 地圖）、電話。
struct ShortcutBar: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var settings: AppSettings
    @State private var showPhone = false
    @State private var failedMessage: LocalizedStringKey?

    var body: some View {
        HStack(spacing: 16) {
            ShortcutButton(title: "shortcut.media", systemImage: "music.note", tint: Color(red: 0.98, green: 0.24, blue: 0.40)) {
                ShortcutLauncher.open(ShortcutLauncher.musicURLs, with: openURL) { failedMessage = "shortcut.failed.music" }
            }
            ShortcutButton(title: "shortcut.navigation", systemImage: "location.north.line.fill", tint: Color(red: 0.25, green: 0.65, blue: 1.0)) {
                ShortcutLauncher.open(ShortcutLauncher.mapsURLs, with: openURL) { failedMessage = "shortcut.failed.maps" }
            }
            ShortcutButton(title: "shortcut.phone", systemImage: "phone.fill", tint: Color(red: 0.25, green: 0.85, blue: 0.45)) {
                showPhone = true
            }
        }
        .sheet(isPresented: $showPhone) {
            PhoneSheet()
                .environmentObject(settings)
                .presentationDetents([.medium])
        }
        .alert(failedMessage ?? "", isPresented: Binding(get: { failedMessage != nil }, set: { if !$0 { failedMessage = nil } })) {
            Button("common.ok", role: .cancel) {}
        }
    }
}

struct ShortcutButton: View {
    var title: LocalizedStringKey
    var systemImage: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 撥號：常用號碼 + 輸入框；先試 tel:，失敗再用 FaceTime。
struct PhoneSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("phone.placeholder", text: $number)
                    .keyboardType(.phonePad)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))

                HStack(spacing: 16) {
                    Button {
                        call(number)
                    } label: {
                        Label("phone.call", systemImage: "phone.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ok)

                    Button {
                        ShortcutLauncher.open(["facetime://"], with: openURL)
                    } label: {
                        Label("phone.facetime", systemImage: "video.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                    }
                    .buttonStyle(.bordered)
                }

                if !settings.favoritePhone.isEmpty {
                    Button {
                        call(settings.favoritePhone)
                    } label: {
                        Label {
                            Text("phone.favorite \(settings.favoritePhone)")
                        } icon: {
                            Image(systemName: "star.fill")
                        }
                        .font(.system(size: 22))
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                    }
                    .buttonStyle(.bordered)
                }

                if failed {
                    Text("shortcut.failed.phone")
                        .foregroundStyle(Theme.warning)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle(Text("shortcut.phone"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func call(_ n: String) {
        failed = false
        ShortcutLauncher.open(ShortcutLauncher.phoneURLs(number: n), with: openURL) { failed = true }
    }
}
