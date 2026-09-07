import AppKit
import Darwin
import Foundation
import OSLog
import PulseCore

/// How users reach us from inside the app: one address, shown in full so it can
/// be copied when no mail client is set up. Every action ends outside Pulse (the
/// mail client or the clipboard); the app never sends anything on its own.
enum SupportLinks {
    static let supportEmail = "hello@pulseticker.app"

    /// Drafts the email in the default mail client through the system compose
    /// service: recipient and subject set, the environment line in the body, and
    /// the diagnostics report attached as a text file. `mailto:` cannot carry the
    /// report (clients truncate long bodies), which is why this is not a URL.
    /// Returns `false` when no mail client can compose, so the caller can fall
    /// back to the clipboard and the visible address.
    @MainActor
    static func composeEmail(environment: String, report: String) -> Bool {
        guard let service = NSSharingService(named: .composeEmail),
              let attachment = try? writeReportFile(report) else { return false }
        service.recipients = [supportEmail]
        service.subject = "Pulse feedback"
        let items: [Any] = ["\n\n---\n\(environment)\n", attachment]
        guard service.canPerform(withItems: items) else { return false }
        service.perform(withItems: items)
        return true
    }

    /// The report as a file the mail client can attach. Lives in the app's temp
    /// directory under a timestamped name, so successive drafts never clash.
    static func writeReportFile(_ report: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pulse-diagnostics-\(formatter.string(from: .now)).txt")
        try report.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Copies the bare address. Returns whether it landed on the pasteboard.
    static func copyEmailAddress() -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([supportEmail as NSString])
    }
}

/// The plain-text report a user pastes into a bug report or email. It describes
/// the install, the data-source configuration, and the recent log lines of this
/// process, and deliberately excludes anything the user typed or holds: symbols,
/// watchlists, positions, searches, credentials, MCP tokens.
@MainActor
enum SupportDiagnostics {
    /// How far back the log excerpt reaches and how many lines it keeps. Both are
    /// bounded so the report stays pasteable into a GitHub form.
    private static let logWindow: TimeInterval = 30 * 60
    private static let logLineLimit = 300

    /// `Pulse 0.15.2 (152) · macOS 26.0 (Build 25A123) · arm64 · Mac16,1`
    static var environmentSummary: String {
        let bundle = Bundle.main
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Pulse"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var parts = [
            "\(name) \(version) (\(build))",
            "macOS \(macOSVersion)",
            architecture,
        ]
        if let model = sysctlString("hw.model") {
            parts.append(model)
        }
        return parts.joined(separator: " · ")
    }

    /// Everything the report says about the running app, as plain values so the
    /// report itself can be exercised without an `AppState` (see the self-test).
    struct Snapshot {
        var host: PulseHost
        var languagePreference: String
        var launchAtLogin: Bool
        var anonymousAnalytics: Bool
        var providers: [(id: String, enabled: Bool)]
        var longbridgeAuth: String
        var longbridgeConnection: String?
        var longbridgeDelayedMarkets: [String]
        var fuyaoConfigured: Bool
        var groupCount: Int
        var symbolCount: Int
        var symbolsPerMarket: [String: Int]
        var mcpStatus: String
    }

    static func snapshot(appState: AppState, host: PulseHost) -> Snapshot {
        let settings = appState.settings
        let store = appState.watchlist
        return Snapshot(
            host: host,
            languagePreference: settings.languagePreference.rawValue,
            launchAtLogin: settings.launchAtLogin,
            anonymousAnalytics: settings.shareAnonymousUsageData,
            providers: appState.providerDescriptors.map { ($0.id, appState.isProviderEnabled($0.id)) },
            longbridgeAuth: longbridgeAuthDescription(appState.longbridgeAuthState),
            longbridgeConnection: appState.longbridgeConfigured
                ? longbridgeConnectionDescription(appState.longbridgeConnectionStatus)
                : nil,
            longbridgeDelayedMarkets: appState.longbridgeDelayedMarkets.map(\.rawValue).sorted(),
            fuyaoConfigured: appState.fuyaoConfigured,
            groupCount: store.groups.count,
            symbolCount: store.allItems.count,
            symbolsPerMarket: Dictionary(grouping: store.allItems, by: \.symbol.market.rawValue)
                .mapValues(\.count),
            mcpStatus: mcpStatusDescription(appState.agentServer?.status)
        )
    }

    static func report(_ snapshot: Snapshot) -> String {
        var lines: [String] = []
        lines.append("# Pulse diagnostics report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: .now))")
        lines.append("Contains app, system, settings, and data-source status plus recent log lines from this session. No symbols, watchlists, positions, searches, or credentials.")
        lines.append("")

        lines.append("## App")
        let bundle = Bundle.main
        lines.append(field("Version", bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
        lines.append(field("Build", bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))
        lines.append(field("Bundle", bundle.bundleIdentifier ?? "?"))
        #if DEBUG
        lines.append(field("Configuration", "Debug"))
        #else
        lines.append(field("Configuration", "Release"))
        #endif
        lines.append(field("Installed in /Applications", bundle.bundleURL.path.hasPrefix("/Applications/") ? "yes" : "no"))
        let updater = SoftwareUpdateController.shared
        lines.append(field("Update feed configured", updater.isConfigured ? "yes" : "no"))
        if let available = updater.availableUpdate {
            lines.append(field("Update available", available.displayVersion))
        }
        lines.append(field("Host", snapshot.host == .pinnedWindow ? "pinned window" : "menu bar"))
        lines.append(field("Process uptime", uptimeDescription))
        lines.append("")

        lines.append("## System")
        lines.append(field("macOS", macOSVersion))
        lines.append(field("Architecture", architecture))
        lines.append(field("Model", sysctlString("hw.model") ?? "unknown"))
        lines.append(field("Locale", Locale.current.identifier))
        lines.append(field("Preferred languages", Locale.preferredLanguages.prefix(3).joined(separator: ", ")))
        lines.append(field("Time zone", TimeZone.current.identifier))
        lines.append("")

        lines.append("## Settings")
        lines.append(field("Language", snapshot.languagePreference))
        lines.append(field("Launch at login", snapshot.launchAtLogin ? "on" : "off"))
        lines.append(field("Anonymous analytics", snapshot.anonymousAnalytics ? "on" : "off"))
        lines.append("")

        lines.append("## Data sources")
        for provider in snapshot.providers {
            lines.append(field(provider.id, provider.enabled ? "enabled" : "disabled"))
        }
        lines.append(field("Longbridge auth", snapshot.longbridgeAuth))
        if let connection = snapshot.longbridgeConnection {
            lines.append(field("Longbridge connection", connection))
        }
        if !snapshot.longbridgeDelayedMarkets.isEmpty {
            lines.append(field("Longbridge delayed markets", snapshot.longbridgeDelayedMarkets.joined(separator: ", ")))
        }
        lines.append(field("Fuyao key saved", snapshot.fuyaoConfigured ? "yes" : "no"))
        lines.append("")

        lines.append("## Watchlist")
        lines.append(field("Groups", String(snapshot.groupCount)))
        lines.append(field("Symbols", String(snapshot.symbolCount)))
        let byMarket = snapshot.symbolsPerMarket.map { "\($0.key)=\($0.value)" }.sorted()
        if !byMarket.isEmpty {
            lines.append(field("Per market", byMarket.joined(separator: ", ")))
        }
        lines.append("")

        lines.append("## Agents (MCP)")
        lines.append(field("Server", snapshot.mcpStatus))
        lines.append("")

        lines.append("## Recent log (last \(Int(logWindow / 60)) min, up to \(logLineLimit) lines)")
        lines.append(contentsOf: recentLogLines())
        return lines.joined(separator: "\n")
    }

    /// Opens a mail draft with the report attached. When that is not possible the
    /// report is copied instead, and the return value says which happened so the
    /// UI can point at the address.
    static func emailReport(appState: AppState, host: PulseHost) -> EmailOutcome {
        let text = report(snapshot(appState: appState, host: host))
        if SupportLinks.composeEmail(environment: environmentSummary, report: text) {
            return .drafted
        }
        return copy(text) ? .copiedInstead : .failed
    }

    enum EmailOutcome {
        case drafted
        case copiedInstead
        case failed
    }

    /// Copies the report to the general pasteboard. Returns whether it landed there.
    static func copyReport(appState: AppState, host: PulseHost) -> Bool {
        copy(report(snapshot(appState: appState, host: host)))
    }

    private static func copy(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([text as NSString])
    }

    // MARK: - Log excerpt

    /// Entries this process wrote under the app's own subsystem, which covers the
    /// Mac target and the PulseCore providers alike. `.currentProcessIdentifier`
    /// is the only scope a sandboxed app may open, and it is the one we want: it
    /// is exactly this session.
    private static func recentLogLines() -> [String] {
        let subsystem = Bundle.main.bundleIdentifier ?? "app.pulse.mac"
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-logWindow))
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            let entries = try store.getEntries(at: position, matching: predicate)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm:ss.SSS"

            var lines: [String] = []
            for case let entry as OSLogEntryLog in entries {
                lines.append(
                    "\(formatter.string(from: entry.date)) \(levelTag(entry.level)) [\(entry.category)] \(entry.composedMessage)"
                )
            }
            if lines.isEmpty {
                return ["(no entries)"]
            }
            if lines.count > logLineLimit {
                let dropped = lines.count - logLineLimit
                lines = Array(lines.suffix(logLineLimit))
                lines.insert("(\(dropped) earlier lines omitted)", at: 0)
            }
            return lines
        } catch {
            return ["(log unavailable: \(error.localizedDescription))"]
        }
    }

    private static func levelTag(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTICE"
        case .error: "ERROR"
        case .fault: "FAULT"
        case .undefined: "LOG"
        @unknown default: "LOG"
        }
    }

    // MARK: - Descriptions

    private static func field(_ name: String, _ value: String) -> String {
        "\(name): \(value)"
    }

    private static func longbridgeAuthDescription(_ state: AppState.LongbridgeAuthState) -> String {
        switch state {
        case .none: "not configured"
        case .apiKey: "API key"
        case .oauth: "OAuth"
        }
    }

    private static func longbridgeConnectionDescription(_ status: LongbridgeConnectionStatus) -> String {
        switch status {
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .reconnecting: "reconnecting"
        case .connected: "connected"
        case .failed(let issue, let detail):
            detail.map { "failed (\(issue)): \($0)" } ?? "failed (\(issue))"
        }
    }

    private static func mcpStatusDescription(_ status: MCPAgentServer.Status?) -> String {
        switch status {
        case .running(let port): "running on 127.0.0.1:\(port)"
        case .failed(let message): "failed: \(message)"
        case .stopped, nil: "stopped"
        }
    }

    private static var uptimeDescription: String {
        guard let start = processStartDate else { return "unknown" }
        let seconds = max(0, Int(Date.now.timeIntervalSince(start)))
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }

    /// The kernel's record of when this process started; there is no Foundation
    /// equivalent, and a lazily initialised static would only date its first use.
    private static var processStartDate: Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000)
    }

    /// `27.0 (26A5425a)`: numeric, unlike `operatingSystemVersionString`, which
    /// is localized and would read differently in every report.
    private static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 {
            text += ".\(version.patchVersion)"
        }
        if let build = sysctlString("kern.osversion") {
            text += " (\(build))"
        }
        return text
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
