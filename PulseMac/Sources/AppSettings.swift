import Foundation
import Observation
import ServiceManagement
import PulseCore

enum MenuBarMode: String, Codable, CaseIterable, Sendable {
    case single, rotate, compact

    var displayName: String {
        switch self {
        case .single: "单标的"
        case .rotate: "轮播"
        case .compact: "紧凑（仅图标）"
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
    /// Red-up/green-down (A-share convention); false means green-up/red-down
    var redUp: Bool = true { didSet { save() } }

    /// Provider ids disabled by the user (all enabled by default)
    var disabledProviderIDs: Set<String> = [] { didSet { save() } }

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
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            // Assignments in a class's init don't trigger didSet, so no redundant saves
            menuBarMode = snapshot.menuBarMode
            primarySymbol = snapshot.primarySymbol
            rotateInterval = snapshot.rotateInterval
            refreshInterval = snapshot.refreshInterval
            redUp = snapshot.redUp
            disabledProviderIDs = snapshot.disabledProviderIDs ?? []
            showPriceInMenuBar = snapshot.showPriceInMenuBar ?? false
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private struct Snapshot: Codable {
        var menuBarMode: MenuBarMode
        var primarySymbol: SymbolID?
        var rotateInterval: TimeInterval
        var refreshInterval: TimeInterval
        var redUp: Bool
        var disabledProviderIDs: Set<String>?
        var showPriceInMenuBar: Bool?
    }

    private func save() {
        let snapshot = Snapshot(menuBarMode: menuBarMode, primarySymbol: primarySymbol,
                                rotateInterval: rotateInterval, refreshInterval: refreshInterval,
                                redUp: redUp, disabledProviderIDs: disabledProviderIDs,
                                showPriceInMenuBar: showPriceInMenuBar)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
