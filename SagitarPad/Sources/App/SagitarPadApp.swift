import SwiftUI
import SagitarCore

@main
struct SagitarPadApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var model = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(settings)
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .onAppear {
                    model.apply(settings: settings)
                    model.select(settings.dataSource)
                }
        }
    }
}
