import AppKit
import Darwin
import Foundation
import OSLog
import SwiftUI

/// A small, process-local diagnostic trail for the native watchlist reorder path.
/// Every checkpoint also goes to the unified log with its fields public, which is
/// how it reaches the support diagnostics report. Nothing leaves the Mac on its
/// own: the user pastes the report themselves. Fields are bounded interaction
/// metadata only; no symbols, positions, or other user content.
@MainActor
final class ReorderDiagnostics {
    static let shared = ReorderDiagnostics()

    private struct Event: Codable {
        let elapsedMilliseconds: Int
        let name: String
        let fields: [String: String]
    }

    private struct Report: Codable {
        struct App: Codable {
            let name: String
            let version: String
            let build: String
            let bundleIdentifier: String
        }

        struct Device: Codable {
            let macOS: String
            let architecture: String
            let modelIdentifier: String?
            let locale: String
        }

        let schemaVersion: Int
        let generatedAt: String
        let feature: String
        let privacyNotice: String
        let app: App
        let device: Device
        let events: [Event]
    }

    private static let maximumEventCount = 200
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pulse.mac.dev",
        category: "WatchlistReorder"
    )
    private var events: [Event] = []
    private var sessionNumber = 0
    private var moveCount = 0

    private init() {
        append("diagnostics.started")
    }

    /// `host` names the surface (menu bar panel or pinned window). The activation
    /// and key-window flags are the first thing to check when a drag never starts:
    /// an accessory app's menu bar panel opens without activating the app, while the
    /// pinned window activates it explicitly.
    func reorderModeEntered(
        itemCount: Int,
        orderMode: String,
        sortOption: String,
        prioritizesOpenMarkets: Bool,
        reduceMotion: Bool,
        host: String,
        window: NSWindow?
    ) {
        sessionNumber += 1
        moveCount = 0
        var fields = [
            "itemCount": String(itemCount),
            "orderMode": orderMode,
            "sortOption": sortOption,
            "prioritizesOpenMarkets": String(prioritizesOpenMarkets),
            "reduceMotion": String(reduceMotion),
            "host": host,
        ]
        fields.merge(Self.windowFields(window)) { _, new in new }
        append("reorder.modeEntered", fields: fields)
    }

    /// Focus and activation changes while the mode is active: a panel that resigns
    /// key the moment the pointer moves explains a drag that never begins.
    func hostEvent(_ name: String, window: NSWindow?) {
        append("host.\(name)", fields: Self.windowFields(window))
    }

    func reorderModeExited() {
        append(
            "reorder.modeExited",
            fields: ["moveCount": String(moveCount)]
        )
    }

    func moveReceived(
        sourceCount: Int,
        destination: Int,
        itemCount: Int,
        committed: Bool
    ) {
        moveCount += 1
        append(
            "reorder.onMove",
            fields: [
                "sourceCount": String(sourceCount),
                "destination": String(destination),
                "itemCount": String(itemCount),
                "committed": String(committed),
            ]
        )
    }

    func pointerDown(horizontalZone: String, clickCount: Int, modifierFlags: UInt, window: NSWindow?) {
        var fields = [
            "horizontalZone": horizontalZone,
            "clickCount": String(clickCount),
            "modifierFlags": String(modifierFlags),
        ]
        fields.merge(Self.windowFields(window)) { _, new in new }
        append("pointer.down", fields: fields)
    }

    func pointerDragStarted(initialDistance: Int) {
        append(
            "pointer.dragStarted",
            fields: ["initialDistancePoints": String(initialDistance)]
        )
    }

    func pointerEnded(
        dragged: Bool,
        dragEventCount: Int,
        maximumDistance: Int,
        durationMilliseconds: Int
    ) {
        append(
            "pointer.ended",
            fields: [
                "dragged": String(dragged),
                "dragEventCount": String(dragEventCount),
                "maximumDistancePoints": String(maximumDistance),
                "durationMilliseconds": String(durationMilliseconds),
            ]
        )
    }

    func pointerCancelled(
        reason: String,
        dragged: Bool,
        dragEventCount: Int,
        maximumDistance: Int,
        durationMilliseconds: Int
    ) {
        append(
            "pointer.cancelled",
            fields: [
                "reason": reason,
                "dragged": String(dragged),
                "dragEventCount": String(dragEventCount),
                "maximumDistancePoints": String(maximumDistance),
                "durationMilliseconds": String(durationMilliseconds),
            ]
        )
    }

    func copyLog() -> Bool {
        do {
            append("diagnostics.copyAttempted")
            let text = String(decoding: try reportData(), as: UTF8.self)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let copied = pasteboard.writeObjects([text as NSString])
            if copied {
                logger.info("Diagnostic log copied by user")
            } else {
                logger.error("Diagnostic log copy failed: pasteboard rejected text")
            }
            return copied
        } catch {
            logger.error("Diagnostic log copy failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func reportData() throws -> Data {
        let bundle = Bundle.main
        let report = Report(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: .now),
            feature: "watchlist.reorder",
            privacyNotice: "Contains app/device metadata and bounded interaction events only. No symbols, watchlists, positions, searches, credentials, or raw system logs are included.",
            app: .init(
                name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Pulse Dev",
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                bundleIdentifier: bundle.bundleIdentifier ?? "unknown"
            ),
            device: .init(
                macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: Self.architecture,
                modelIdentifier: Self.sysctlString("hw.model"),
                locale: Locale.current.identifier
            ),
            events: events
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    private func append(_ name: String, fields: [String: String] = [:]) {
        var scopedFields = fields
        if sessionNumber > 0 {
            scopedFields["session"] = String(sessionNumber)
        }
        events.append(Event(
            elapsedMilliseconds: Int(
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            ),
            name: name,
            fields: scopedFields
        ))
        if events.count > Self.maximumEventCount {
            events.removeFirst(events.count - Self.maximumEventCount)
        }
        let rendered = scopedFields.keys.sorted().map { "\($0)=\(scopedFields[$0]!)" }.joined(separator: " ")
        logger.info("Reorder checkpoint \(name, privacy: .public) \(rendered, privacy: .public)")
    }

    /// What the host looked like at that instant. `window` is nil when the view is
    /// not in a window yet, which is itself worth knowing.
    private static func windowFields(_ window: NSWindow?) -> [String: String] {
        // `NSApp` is nil until the application object exists (launch-time self-tests).
        let app: NSApplication? = NSApp
        var fields = ["appActive": app.map { String($0.isActive) } ?? "noApp"]
        guard let window else {
            fields["window"] = "none"
            return fields
        }
        fields["window"] = String(describing: type(of: window))
        fields["windowKey"] = String(window.isKeyWindow)
        fields["windowVisible"] = String(window.isVisible)
        fields["windowLevel"] = String(window.level.rawValue)
        fields["canBecomeKey"] = String(window.canBecomeKey)
        return fields
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

}

/// Observes the native pointer sequence without consuming it. This is intentionally
/// outside the rows: observing a row with a SwiftUI gesture would compete with List's
/// AppKit drag recognizer and could change the behavior we are trying to diagnose.
///
/// Reading the trail: once NSTableView starts its AppKit drag session, that session
/// runs its own event loop and this monitor stops seeing the sequence. A successful
/// drag therefore looks like `pointer.down`, at most a few drag events, then
/// `reorder.onMove`; the eventual `pointer.ended` may report `dragged=false` and a
/// tiny distance. That is normal. The failure signature is the opposite: a long,
/// wide pointer sequence (`dragEventCount` high, `maximumDistancePoints` large)
/// with no `reorder.onMove` at all, meaning the table never began a drag session.
struct ReorderPointerMonitor: NSViewRepresentable {
    let enabled: Bool

    func makeNSView(context: Context) -> ReorderPointerMonitorView {
        let view = ReorderPointerMonitorView()
        view.setEnabled(enabled)
        return view
    }

    func updateNSView(_ view: ReorderPointerMonitorView, context: Context) {
        view.setEnabled(enabled)
    }

    static func dismantleNSView(_ view: ReorderPointerMonitorView, coordinator: ()) {
        view.stopMonitoring(reason: "viewDismantled")
    }
}

@MainActor
final class ReorderPointerMonitorView: NSView {
    private var monitor: Any?
    private var hostObservers: [NSObjectProtocol] = []
    private var isEnabled = false
    private var pointerStart: (location: CGPoint, timestamp: TimeInterval)?
    private var dragEventCount = 0
    private var maximumDistance: CGFloat = 0
    private var didStartDragging = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeMonitor()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        if !enabled {
            stopMonitoring(reason: "reorderModeEnded")
        }
        synchronizeMonitor()
    }

    func stopMonitoring(reason: String) {
        if let pointerStart {
            let duration = max(0, ProcessInfo.processInfo.systemUptime - pointerStart.timestamp)
            ReorderDiagnostics.shared.pointerCancelled(
                reason: reason,
                dragged: didStartDragging,
                dragEventCount: dragEventCount,
                maximumDistance: Int(maximumDistance.rounded()),
                durationMilliseconds: Int((duration * 1_000).rounded())
            )
        }
        resetPointerSequence()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        for observer in hostObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        hostObservers = []
    }

    private func synchronizeMonitor() {
        guard isEnabled, monitor == nil, let hostWindow = window else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.observe(event)
            return event
        }

        // Focus and activation transitions during the mode. The window ones are
        // scoped to this host; the app ones are global by nature.
        let center = NotificationCenter.default
        let windowEvents: [(Notification.Name, String)] = [
            (NSWindow.didBecomeKeyNotification, "windowBecameKey"),
            (NSWindow.didResignKeyNotification, "windowResignedKey"),
            (NSWindow.willCloseNotification, "windowWillClose"),
        ]
        for (name, label) in windowEvents {
            hostObservers.append(center.addObserver(forName: name, object: hostWindow, queue: .main) { [weak hostWindow] _ in
                MainActor.assumeIsolated {
                    ReorderDiagnostics.shared.hostEvent(label, window: hostWindow)
                }
            })
        }
        let appEvents: [(Notification.Name, String)] = [
            (NSApplication.didBecomeActiveNotification, "appBecameActive"),
            (NSApplication.didResignActiveNotification, "appResignedActive"),
        ]
        for (name, label) in appEvents {
            hostObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak hostWindow] _ in
                MainActor.assumeIsolated {
                    ReorderDiagnostics.shared.hostEvent(label, window: hostWindow)
                }
            })
        }
    }

    private func observe(_ event: NSEvent) {
        guard isEnabled, let hostWindow = window, event.window === hostWindow else { return }

        switch event.type {
        case .leftMouseDown:
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return }
            pointerStart = (location, event.timestamp)
            dragEventCount = 0
            maximumDistance = 0
            didStartDragging = false
            ReorderDiagnostics.shared.pointerDown(
                horizontalZone: horizontalZone(for: location.x),
                clickCount: event.clickCount,
                modifierFlags: event.modifierFlags.rawValue,
                window: hostWindow
            )

        case .leftMouseDragged:
            guard let pointerStart else { return }
            dragEventCount += 1
            let location = convert(event.locationInWindow, from: nil)
            maximumDistance = max(
                maximumDistance,
                hypot(location.x - pointerStart.location.x, location.y - pointerStart.location.y)
            )
            if !didStartDragging, maximumDistance >= 3 {
                didStartDragging = true
                ReorderDiagnostics.shared.pointerDragStarted(
                    initialDistance: Int(maximumDistance.rounded())
                )
            }

        case .leftMouseUp:
            guard let pointerStart else { return }
            let duration = max(0, event.timestamp - pointerStart.timestamp)
            ReorderDiagnostics.shared.pointerEnded(
                dragged: didStartDragging,
                dragEventCount: dragEventCount,
                maximumDistance: Int(maximumDistance.rounded()),
                durationMilliseconds: Int((duration * 1_000).rounded())
            )
            resetPointerSequence()

        default:
            break
        }
    }

    private func horizontalZone(for x: CGFloat) -> String {
        guard bounds.width > 0 else { return "unknown" }
        let fraction = x / bounds.width
        if fraction < 0.25 { return "leading" }
        if fraction > 0.75 { return "trailing" }
        return "middle"
    }

    private func resetPointerSequence() {
        pointerStart = nil
        dragEventCount = 0
        maximumDistance = 0
        didStartDragging = false
    }
}
