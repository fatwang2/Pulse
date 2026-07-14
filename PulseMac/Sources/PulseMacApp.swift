import SwiftUI
import PulseCore

/// Receives custom-scheme URLs (the Longbridge OAuth callback). A menu bar app's popover
/// view hierarchy may not be alive when the browser redirects back, so the app delegate is
/// the reliable entry point rather than `onOpenURL`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var urlHandler: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Self.urlHandler?(url)
        }
    }
}

@main
struct PulseMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState: AppState

    init() {
        SelfTest.runIfRequested()
        SoftwareUpdateController.shared.start()
        let state = AppState()
        _appState = State(initialValue: state)
        AppDelegate.urlHandler = { url in state.handleOAuthCallback(url) }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environment(appState)
                .environment(\.locale, appState.settings.locale)
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
