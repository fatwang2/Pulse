import SwiftUI
import PulseCore

@main
struct PulseiOSApp: App {
    @State private var appState = IOSAppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchlistScreen()
                .environment(appState)
        }
        .onChange(of: scenePhase) { _, phase in
            appState.scenePhaseChanged(phase)
        }
    }
}
