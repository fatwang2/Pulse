import Foundation
import Observation
import PulseCore

/// iOS settings: the Mac snapshot's cross-platform subset, stored under its own
/// key so the two clients never fight over one blob (they don't share defaults
/// today, but the schemas would drift apart even if they did).
@MainActor
@Observable
final class IOSSettings {
    /// Red-up/green-down (A-share convention); false means green-up/red-down.
    var redUp: Bool = true { didSet { save() } }
    /// Show US pre/post-market sessions on every intraday chart (on by default).
    var showsUSExtendedHours: Bool = true { didSet { save() } }
    /// Last resolution chosen from the detail chart's period picker.
    var lastCandlePeriod: CandlePeriod = .minute1 { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String
    /// `@Observable` routes init-time assignments through `didSet`; suppress
    /// persistence until the stored snapshot has been restored.
    @ObservationIgnored private var isInitializing = true

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "pulse.ios.settings.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            redUp = snapshot.redUp
            showsUSExtendedHours = snapshot.showsUSExtendedHours ?? true
            lastCandlePeriod = snapshot.lastCandlePeriod ?? .minute1
        }
        isInitializing = false
    }

    private struct Snapshot: Codable {
        var redUp: Bool
        var showsUSExtendedHours: Bool?
        var lastCandlePeriod: CandlePeriod?
    }

    private func save() {
        guard !isInitializing else { return }
        let snapshot = Snapshot(
            redUp: redUp,
            showsUSExtendedHours: showsUSExtendedHours,
            lastCandlePeriod: lastCandlePeriod
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
