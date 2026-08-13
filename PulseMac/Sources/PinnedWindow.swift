import AppKit
import Combine
import SwiftUI

/// Which surface is hosting the root view.
///
/// The menu bar panel is closed by the system the moment it stops being key, and
/// `MenuBarExtra` exposes no way to opt out. "Pinning" therefore re-hosts the same
/// view tree in a standalone floating window instead of trying to keep the panel up.
/// Both hosts read and write the one shared `AppState`, so they stay in lockstep.
enum PulseHost: Hashable {
    case menuBar
    case pinnedWindow
}

extension EnvironmentValues {
    @Entry var pulseHost: PulseHost = .menuBar
}

@MainActor
enum PinnedWindow {
    static let id = "pulse.pinned"

    /// Top-left of the panel at the moment the user pinned, in AppKit screen coordinates.
    /// The first pin adopts it so the action reads as the panel detaching in place, under
    /// the menu bar icon the user was already looking at, instead of the watchlist
    /// teleporting to the middle of the screen. Once the window has a remembered position
    /// that takes over. Consumed by the next window created; an existing window is left
    /// wherever it is.
    static var pendingTopLeft: CGPoint?

    /// An accessory (`LSUIElement`) app is not frontmost when the panel is open, so a
    /// newly opened window would come up behind whatever the user was working in.
    /// Activating also resigns the panel's key status, which is what closes it.
    static func activate() {
        NSApp.activate()
    }
}

extension PinnedWindow {
    /// Applies the window traits the SwiftUI scene modifiers don't cover, and consumes a
    /// pending placement if one is waiting.
    ///
    /// Everything is applied twice on purpose: SwiftUI finishes configuring and centering
    /// a newly presented window scene around the time the content attaches, so the first
    /// pass alone gets overwritten. The second lands after that and wins; when nothing
    /// overrides the first, both write the same values and there is no visible jump.
    ///
    /// Anchoring the top-left also gives route pushes the right growth direction:
    /// `setContentSize` pins that corner, so a taller page extends downward instead of
    /// drifting the header out from under the pointer.
    static func configure(_ window: NSWindow, settings: AppSettings) {
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        // A remembered position always wins: once the user has placed this window, every
        // way of bringing it back — re-pinning, or a relaunch — returns it there. The
        // panel anchor is the fallback for the very first pin, when there is nothing to
        // remember yet and detaching in place is what explains the action.
        let target = settings.pinnedWindowTopLeft ?? pendingTopLeft
        pendingTopLeft = nil
        let placement = target.flatMap { isReachable($0) ? $0 : nil }
        apply(to: window, topLeft: placement)
        DispatchQueue.main.async { apply(to: window, topLeft: placement) }
    }

    private static func apply(to window: NSWindow, topLeft: CGPoint?) {
        guard let topLeft else { return }
        window.setFrameTopLeftPoint(topLeft)
    }

    /// Guards against restoring onto a display that is no longer attached, which would
    /// strand the window off screen with no way to drag it back. AppKit's standard
    /// top-aligned window has `topLeft.y == visibleFrame.maxY`; `CGRect.contains` excludes
    /// that maximum edge, so compare inclusively instead.
    private static func isReachable(_ topLeft: CGPoint) -> Bool {
        NSScreen.screens.contains { screen in
            let frame = screen.visibleFrame
            return topLeft.x >= frame.minX && topLeft.x <= frame.maxX
                && topLeft.y >= frame.minY && topLeft.y <= frame.maxY
        }
    }
}

/// Wraps the pinned window's content so the AppKit-level setup runs on every
/// presentation.
///
/// Both hooks are needed: SwiftUI keeps this scene's `NSWindow` alive across close and
/// reopen, so `viewDidMoveToWindow` fires only for the first attach, while `onAppear`
/// fires for each presentation but can run before the window reference resolves.
/// Whichever comes first consumes the pending placement; the other finds nothing to do.
struct PinnedWindowHost<Content: View>: View {
    let settings: AppSettings
    @ViewBuilder let content: Content
    @State private var window: NSWindow?

    var body: some View {
        content
            .background {
                HostWindowReader { resolved in
                    window = resolved
                    if let resolved { PinnedWindow.configure(resolved, settings: settings) }
                }
            }
            .onAppear {
                guard let window else { return }
                PinnedWindow.configure(window, settings: settings)
            }
            // Records both user drags and the anchoring above, so the position the window
            // is at when the app quits is the one it comes back to.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { note in
                guard let moved = note.object as? NSWindow, moved === window else { return }
                settings.pinnedWindowTopLeft = CGPoint(x: moved.frame.minX, y: moved.frame.maxY)
            }
    }
}

/// Reports the `NSWindow` currently hosting the view.
///
/// The menu bar panel is not a scene, so `dismissWindow` cannot reach it, and it only
/// self-closes on a click *outside* itself — pinning is a click inside. Closing it needs
/// a direct reference, and reading it from the view hierarchy avoids matching SwiftUI's
/// private panel class by name.
struct HostWindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HostWindowReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? HostWindowReaderView)?.onChange = onChange
    }
}

private final class HostWindowReaderView: NSView {
    var onChange: (NSWindow?) -> Void = { _ in }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onChange(window)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
