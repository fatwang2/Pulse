import AppKit
import SwiftUI
import PulseCore
import PulseUI

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
        PulseTelemetry.configure(collectionEnabled: state.settings.shareAnonymousUsageData)
        PulseTelemetry.signal(.appLaunched)
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

    private var templateIcon: NSImage {
        let canvasSize = NSSize(width: 16, height: 16)
        guard let source = NSImage(named: "PulseMenuBarIcon") else {
            let fallback = NSImage(
                systemSymbolName: "waveform.path.ecg",
                accessibilityDescription: "Pulse"
            ) ?? NSImage(size: canvasSize)
            fallback.size = canvasSize
            fallback.isTemplate = true
            return fallback
        }

        let image = NSImage(size: canvasSize, flipped: false) { rect in
            let aspectRatio = source.size.width / source.size.height
            let waveformHeight = rect.width / aspectRatio
            source.draw(
                in: NSRect(
                    x: rect.minX,
                    y: rect.midY - waveformHeight / 2,
                    width: rect.width,
                    height: waveformHeight
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    var body: some View {
        // Icon only by default; price text appears only after the user enables "show quotes in menu bar" in settings
        if !appState.settings.showPriceInMenuBar || appState.watchlist.isEmpty {
            Image(nsImage: templateIcon)
                .accessibilityLabel("Pulse")
        } else {
            Text(appState.menuBarText)
                .font(.system(size: 12).monospacedDigit())
        }
    }
}
