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
    /// Launching the already-running app again (Applications double-click, Spotlight)
    /// is the one gesture an accessory app can answer visibly. Presenting the floating
    /// window is that answer; silence here reads as "the app didn't start".
    static var reopenHandler: (() -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Self.urlHandler?(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.reopenHandler?()
        return false
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
        // Decided once here, not read live in `body`: the welcome item is marked seen
        // while the window is up, and launch behavior must not flip mid-session.
        state.onboarding.welcomeSessionActive = state.onboarding.shouldPresentWelcomeWindow
        _appState = State(initialValue: state)
        AppDelegate.urlHandler = { url in state.handleOAuthCallback(url) }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environment(appState)
                .environment(\.locale, appState.settings.locale)
                .environment(\.pulseHost, .menuBar)
                .background(.thickMaterial)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)

        // The pinned host: the same view tree in a floating window that outlives losing
        // focus. Sized by its content, so route pushes resize the window exactly the way
        // they resize the panel.
        // Deliberately title-less. The title bar is the Mac-native home for a window's
        // identity, but at 340pt wide there is not room for both a title and the action
        // group: macOS collapses the whole toolbar into a `»` overflow button, burying
        // four one-click actions in a submenu. The actions win; the app's identity is
        // already carried by the Dock icon and the menu bar item.
        Window("Pulse", id: PinnedWindow.id) {
            PinnedWindowHost(settings: appState.settings) {
                PopoverRootView()
                    .environment(appState)
                    .environment(\.locale, appState.settings.locale)
                    .environment(\.pulseHost, .pinnedWindow)
                    .containerBackground(.thickMaterial, for: .window)
                    .onAppear {
                        appState.settings.pinnedWindowVisible = true
                        if appState.onboarding.welcomeSessionActive {
                            appState.onboarding.markSeen(.welcomeWindow)
                            // An accessory app is not frontmost at launch, so the
                            // welcome window would otherwise come up behind whatever
                            // the user was working in.
                            PinnedWindow.activate()
                        }
                    }
                    .onDisappear {
                        appState.settings.pinnedWindowVisible = false
                        appState.onboarding.welcomeSessionActive = false
                        // A tour interrupted by the window closing resumes at the
                        // same stop in whichever host shows the list next.
                        appState.onboarding.pauseTour()
                    }
            }
        }
        // Not `.plain`: it would drop the empty 32pt title bar strip and give the panel's
        // header the window's first row, but a plain window is borderless, and AppKit
        // will not make a borderless window key. Verified on macOS 26: the search field
        // ignores every keystroke, Cmd-W and Cmd-C are dead, and clicking the window
        // never brings the app forward. Forcing `fullSizeContentView` under a titled
        // style does not help either — SwiftUI lays scene content out below the title bar
        // regardless. The strip stays; it is also the drag handle and close button.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        // Presentation at launch is decided by the persisted pin state, plus exactly one
        // exception: the very first launch presents the window so the app visibly exists.
        // SwiftUI's own restoration is disabled to keep this the single source of truth.
        .defaultLaunchBehavior(
            appState.settings.pinnedWindowVisible || appState.onboarding.welcomeSessionActive
                ? .presented : .suppressed
        )
        .restorationBehavior(.disabled)
    }
}

struct MenuBarLabel: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

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
        Group {
            // Icon only by default; price text appears only after the user enables "show quotes in menu bar" in settings
            if !appState.settings.showPriceInMenuBar || appState.watchlist.isEmpty {
                Image(nsImage: templateIcon)
                    .accessibilityLabel("Pulse")
            } else {
                Text(appState.menuBarText)
                    .font(.system(size: 12).monospacedDigit())
            }
        }
        // The label is the one view alive for the app's whole lifetime, which makes it
        // the only reliable place to hand the AppKit delegate a scene-scoped action.
        .onAppear {
            AppDelegate.reopenHandler = {
                openWindow(id: PinnedWindow.id)
                PinnedWindow.activate()
            }
        }
    }
}
