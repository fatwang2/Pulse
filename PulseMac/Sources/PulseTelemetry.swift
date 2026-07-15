import Foundation
import OSLog
import TelemetryDeck

enum PulseTelemetryEvent: String, Sendable {
    case appLaunched = "app.launched"
    case popoverOpened = "popover.opened"
    case settingsOpened = "settings.opened"
    case manualRefreshRequested = "refresh.manualRequested"
    case collectionEnabled = "settings.analyticsEnabled"
}

/// The app's only analytics boundary. Event payloads deliberately contain no symbols,
/// watchlist data, positions, search text, credentials, or other user-provided content.
@MainActor
enum PulseTelemetry {
    private static let infoKey = "TelemetryDeckAppID"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pulse.mac",
        category: "Telemetry"
    )
    private static var configuration: TelemetryDeck.Config?

    static func configure(collectionEnabled: Bool) {
        guard configuration == nil else { return }
        guard let appID = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
              !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !appID.contains("$(") else {
            logger.notice("Telemetry disabled: TelemetryDeckAppID is not configured")
            return
        }

        let subsystem = Bundle.main.bundleIdentifier ?? "app.pulse.mac"
        let sdkLogger = Logger(subsystem: subsystem, category: "Telemetry")
        let config = TelemetryDeck.Config(appID: appID)
        config.analyticsDisabled = !collectionEnabled
        config.defaultSignalPrefix = "Pulse."
        config.sendNewSessionBeganSignal = false
        config.sessionStatsEnabled = false
        config.logHandler = LogHandler(logLevel: .info) { level, message in
            switch level {
            case .debug:
                sdkLogger.debug("TelemetryDeck: \(message, privacy: .public)")
            case .info:
                sdkLogger.info("TelemetryDeck: \(message, privacy: .public)")
            case .error:
                sdkLogger.error("TelemetryDeck: \(message, privacy: .public)")
            }
        }

        TelemetryDeck.initialize(config: config)
        configuration = config
        logger.info("Telemetry initialized; collection enabled: \(collectionEnabled, privacy: .public)")
    }

    static func setCollectionEnabled(_ enabled: Bool) {
        guard let configuration else { return }
        let wasDisabled = configuration.analyticsDisabled
        configuration.analyticsDisabled = !enabled
        logger.info("Telemetry collection enabled: \(enabled, privacy: .public)")

        if enabled && wasDisabled {
            signal(.collectionEnabled)
        }
    }

    static func signal(_ event: PulseTelemetryEvent) {
        guard let configuration, !configuration.analyticsDisabled else { return }
        TelemetryDeck.signal(event.rawValue)
        logger.info("Telemetry event queued: \(event.rawValue, privacy: .public)")
    }
}
