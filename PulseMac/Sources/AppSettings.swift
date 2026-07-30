import Foundation
import Observation
import ServiceManagement
import PulseCore

enum MenuBarMode: String, Codable, CaseIterable, Sendable {
    case single, rotate, compact

    var displayName: String {
        switch self {
        case .single: PulseLocalization.localizedString("menuBarMode.single")
        case .rotate: PulseLocalization.localizedString("menuBarMode.rotate")
        case .compact: PulseLocalization.localizedString("menuBarMode.compact")
        }
    }
}

enum WatchRowMetricMode: String, Codable, CaseIterable, Sendable {
    case changePercent
    case todayPnL
    case totalPnL
    case summary

    static var allCases: [WatchRowMetricMode] {
        [.changePercent, .todayPnL, .totalPnL]
    }

    var displayName: String {
        switch self {
        case .changePercent: PulseLocalization.localizedString("metric.changePercent")
        case .todayPnL: PulseLocalization.localizedString("metric.todayPnL")
        case .totalPnL: PulseLocalization.localizedString("metric.totalPnL")
        case .summary: PulseLocalization.localizedString("metric.totalPnL")
        }
    }

    var next: WatchRowMetricMode {
        switch self {
        case .changePercent:
            .todayPnL
        case .todayPnL:
            .totalPnL
        case .totalPnL, .summary:
            .changePercent
        }
    }

    var systemImage: String {
        switch self {
        case .changePercent:
            "percent"
        case .todayPnL:
            "calendar"
        case .totalPnL, .summary:
            "briefcase"
        }
    }
}

extension MarketState {
    var extendedSessionLabel: String? {
        switch self {
        case .preMarket:
            PulseLocalization.localizedString("marketState.preMarket")
        case .postMarket:
            PulseLocalization.localizedString("marketState.postMarket")
        case .overnight:
            PulseLocalization.localizedString("marketState.overnight")
        case .regular, .closed:
            nil
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    /// Show quote text (price/change) in the menu bar. Off by default: icon only — subtle and space-saving
    var showPriceInMenuBar: Bool = false { didSet { save() } }

    var menuBarMode: MenuBarMode = .rotate { didSet { save() } }
    /// The symbol pinned in single mode; nil falls back to the first watchlist item
    var primarySymbol: SymbolID? { didSet { save() } }
    var rotateInterval: TimeInterval = 6 { didSet { save() } }
    /// The tag used by menu-bar rotation. Nil resolves to the first available group.
    var rotateGroupID: UUID? { didSet { save() } }
    /// Per-provider quote poll cadence overrides; a missing key falls back to the
    /// provider's suggested interval. Replaces the former global refresh interval.
    var providerPollIntervals: [String: TimeInterval] = [:] { didSet { save() } }
    var watchRowMetricMode: WatchRowMetricMode = .totalPnL { didSet { save() } }
    /// Red-up/green-down (A-share convention); false means green-up/red-down
    var redUp: Bool = true { didSet { save() } }
    /// Show US pre/post-market sessions on every intraday chart (on by default).
    var showsUSExtendedHours: Bool = true { didSet { save() } }
    /// Last resolution chosen from the intraday candlestick menu.
    var minuteCandlePeriod: CandlePeriod = .minute5 { didSet { save() } }
    var languagePreference: PulseLanguagePreference = .system {
        didSet {
            UserDefaults.standard.set(languagePreference.rawValue, forKey: PulseLocalization.languagePreferenceKey)
            save()
        }
    }

    /// Anonymous product analytics only. Event definitions live in PulseTelemetry and
    /// intentionally never include symbols, watchlists, positions, or search content.
    var shareAnonymousUsageData: Bool = true {
        didSet {
            PulseTelemetry.setCollectionEnabled(shareAnonymousUsageData)
            save()
        }
    }

    /// Provider ids disabled by the user (all enabled by default)
    var disabledProviderIDs: Set<String> = [] { didSet { save() } }

    /// Most-recent-first market search queries, capped, user-clearable from the search panel.
    var recentSearchQueries: [String] = [] { didSet { save() } }

    private static let recentSearchLimit = 8

    func recordRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var queries = recentSearchQueries.filter {
            $0.caseInsensitiveCompare(trimmed) != .orderedSame
        }
        queries.insert(trimmed, at: 0)
        recentSearchQueries = Array(queries.prefix(Self.recentSearchLimit))
    }

    func clearRecentSearches() {
        recentSearchQueries = []
    }

    var locale: Locale {
        PulseLocalization.currentLocale
    }

    var launchAtLogin: Bool = false {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = oldValue
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String
    /// `@Observable` turns tracked properties into computed accessors, so assignments made
    /// while this class is initializing can still reach their `didSet` observers. Suppress
    /// persistence until every property has been restored to avoid replacing the stored
    /// snapshot with declaration defaults before it has been read.
    @ObservationIgnored private var isInitializing = true

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "pulse.settings.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        var loadedSnapshot = false
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            loadedSnapshot = true
            menuBarMode = snapshot.menuBarMode
            primarySymbol = snapshot.primarySymbol
            rotateInterval = snapshot.rotateInterval
            rotateGroupID = snapshot.rotateGroupID
            providerPollIntervals = snapshot.providerPollIntervals ?? [:]
            watchRowMetricMode = switch snapshot.watchRowMetricMode {
            case .changePercent, .todayPnL, .totalPnL:
                snapshot.watchRowMetricMode!
            case .summary:
                .totalPnL
            case nil:
                .totalPnL
            }
            redUp = snapshot.redUp
            showsUSExtendedHours = snapshot.showsUSExtendedHours ?? true
            if let restoredPeriod = snapshot.minuteCandlePeriod, restoredPeriod.isMinuteK {
                minuteCandlePeriod = restoredPeriod
            }
            disabledProviderIDs = snapshot.disabledProviderIDs ?? []
            recentSearchQueries = snapshot.recentSearchQueries ?? []
            showPriceInMenuBar = snapshot.showPriceInMenuBar ?? false
            languagePreference = snapshot.languagePreference ?? .system
            shareAnonymousUsageData = snapshot.shareAnonymousUsageData ?? true
            UserDefaults.standard.set(languagePreference.rawValue, forKey: PulseLocalization.languagePreferenceKey)
        } else {
            languagePreference = PulseLocalization.currentPreference
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isInitializing = false
        if loadedSnapshot {
            // Rewrite a legacy crypto primarySymbol using SymbolID's structured format.
            save()
        }
    }

    private struct Snapshot: Codable {
        var menuBarMode: MenuBarMode
        var primarySymbol: SymbolID?
        var rotateInterval: TimeInterval
        var rotateGroupID: UUID?
        var watchRowMetricMode: WatchRowMetricMode?
        var redUp: Bool
        var showsUSExtendedHours: Bool?
        var minuteCandlePeriod: CandlePeriod?
        var disabledProviderIDs: Set<String>?
        var recentSearchQueries: [String]?
        var showPriceInMenuBar: Bool?
        var languagePreference: PulseLanguagePreference?
        var providerPollIntervals: [String: TimeInterval]?
        var shareAnonymousUsageData: Bool?
    }

    private func save() {
        guard !isInitializing else { return }
        let snapshot = Snapshot(menuBarMode: menuBarMode, primarySymbol: primarySymbol,
                                rotateInterval: rotateInterval,
                                rotateGroupID: rotateGroupID,
                                watchRowMetricMode: watchRowMetricMode, redUp: redUp,
                                showsUSExtendedHours: showsUSExtendedHours,
                                minuteCandlePeriod: minuteCandlePeriod,
                                disabledProviderIDs: disabledProviderIDs,
                                recentSearchQueries: recentSearchQueries,
                                showPriceInMenuBar: showPriceInMenuBar,
                                languagePreference: languagePreference,
                                providerPollIntervals: providerPollIntervals,
                                shareAnonymousUsageData: shareAnonymousUsageData)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
