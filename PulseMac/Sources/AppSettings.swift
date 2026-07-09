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
    var refreshInterval: TimeInterval = 15 { didSet { save() } }
    var watchRowMetricMode: WatchRowMetricMode = .totalPnL { didSet { save() } }
    /// Red-up/green-down (A-share convention); false means green-up/red-down
    var redUp: Bool = true { didSet { save() } }
    var languagePreference: PulseLanguagePreference = .system {
        didSet {
            UserDefaults.standard.set(languagePreference.rawValue, forKey: PulseLocalization.languagePreferenceKey)
            save()
        }
    }

    /// Provider ids disabled by the user (all enabled by default)
    var disabledProviderIDs: Set<String> = [] { didSet { save() } }

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
    @ObservationIgnored private let storageKey = "pulse.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        languagePreference = PulseLocalization.currentPreference
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            // Assignments in a class's init don't trigger didSet, so no redundant saves
            menuBarMode = snapshot.menuBarMode
            primarySymbol = snapshot.primarySymbol
            rotateInterval = snapshot.rotateInterval
            refreshInterval = snapshot.refreshInterval
            watchRowMetricMode = switch snapshot.watchRowMetricMode {
            case .changePercent, .todayPnL, .totalPnL:
                snapshot.watchRowMetricMode!
            case .summary:
                .totalPnL
            case nil:
                .totalPnL
            }
            redUp = snapshot.redUp
            disabledProviderIDs = snapshot.disabledProviderIDs ?? []
            showPriceInMenuBar = snapshot.showPriceInMenuBar ?? false
            languagePreference = snapshot.languagePreference ?? .system
            UserDefaults.standard.set(languagePreference.rawValue, forKey: PulseLocalization.languagePreferenceKey)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private struct Snapshot: Codable {
        var menuBarMode: MenuBarMode
        var primarySymbol: SymbolID?
        var rotateInterval: TimeInterval
        var refreshInterval: TimeInterval
        var watchRowMetricMode: WatchRowMetricMode?
        var redUp: Bool
        var disabledProviderIDs: Set<String>?
        var showPriceInMenuBar: Bool?
        var languagePreference: PulseLanguagePreference?
    }

    private func save() {
        let snapshot = Snapshot(menuBarMode: menuBarMode, primarySymbol: primarySymbol,
                                rotateInterval: rotateInterval, refreshInterval: refreshInterval,
                                watchRowMetricMode: watchRowMetricMode, redUp: redUp,
                                disabledProviderIDs: disabledProviderIDs,
                                showPriceInMenuBar: showPriceInMenuBar,
                                languagePreference: languagePreference)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
