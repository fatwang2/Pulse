import SwiftUI
import PulseCore

@main
struct PulseMacApp: App {
    @State private var appState = AppState()

    init() {
        SelfTest.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environment(appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let appState: AppState

    var body: some View {
        // Icon only by default; price text appears only after the user enables "show quotes in menu bar" in settings
        if !appState.settings.showPriceInMenuBar || appState.watchlist.isEmpty {
            Image(systemName: "waveform.path.ecg")
        } else {
            Text(appState.menuBarText)
                .font(.system(size: 12).monospacedDigit())
        }
    }
}
