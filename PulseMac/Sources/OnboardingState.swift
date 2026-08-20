import Foundation
import Observation

/// One-time guidance moments: which have been shown, and whether this install is
/// new enough to see them at all.
///
/// Two rules keep this honest across releases:
/// - Every item id carries a version suffix. Re-shipping a redesigned moment is a
///   suffix bump, which re-shows it to everyone exactly once.
/// - Upgraders are grandfathered: an install that already has watchlist data when
///   this ledger first runs marks every current item as seen. Guidance written for
///   a later feature can still reach them by comparing `firstSeenVersion` against
///   the version that introduced it.
@MainActor
@Observable
final class OnboardingState {
    enum Item: String, CaseIterable {
        /// The floating window presented automatically on the very first launch.
        case welcomeWindow = "welcomeWindow.v1"
        /// The step-by-step bubble tour over the header actions, offered once the
        /// first symbol exists. Completing or skipping it retires it for good.
        case featureTour = "featureTour.v1"
    }

    /// The bubble tour's stops, in order: add a symbol, open its detail, switch
    /// the chart to daily candles there, and finally the pin back on the list.
    enum TourStep: Int, CaseIterable {
        case search
        case detail
        case kline
        case pin

        var next: TourStep? { TourStep(rawValue: rawValue + 1) }
        var previous: TourStep? { TourStep(rawValue: rawValue - 1) }

        /// An action step completes by doing, not by a Next button: searching
        /// (or a first symbol arriving) and opening a detail page.
        var isActionStep: Bool { self == .search || self == .detail }

        /// Whether a later stop may step back to this one. Action steps are done
        /// and gone, and the candle stop's anchor lives on the detail page.
        var supportsReturn: Bool { self == .pin }

        /// The pin stop is an epilogue — a contextual tip once the user is back
        /// on the list — not a numbered step left dangling while they explore
        /// the chart the previous step just opened.
        var numberedPosition: Int? { self == .pin ? nil : rawValue + 1 }

        static var numberedCount: Int { allCases.count(where: { $0.numberedPosition != nil }) }
    }

    /// True while the auto-presented welcome window is on screen; keeps the launch
    /// presentation decision stable for the whole session.
    var welcomeSessionActive = false

    /// The bubble currently on screen; nil while the tour is idle or over.
    /// Presentation state lives here rather than in a view so the two hosts share
    /// one tour and closing a host pauses it instead of forking it.
    var activeTourStep: TourStep?
    /// Where a paused tour picks back up. In-memory by design: only completing or
    /// skipping is worth remembering across launches, via the seen ledger.
    private(set) var tourResumeStep: TourStep = .search

    var tourAvailable: Bool { !hasSeen(.featureTour) }

    func beginTourIfNeeded() {
        guard tourAvailable, activeTourStep == nil else { return }
        activeTourStep = tourResumeStep
    }

    func advanceTour() {
        guard let step = activeTourStep else { return }
        if let next = step.next {
            tourResumeStep = next
            // Advancing from the candle stop crosses pages: its successor's
            // anchor is back on the list, so the bubble waits for the return.
            activeTourStep = step == .kline ? nil : next
        } else {
            endTour()
        }
    }

    func regressTour() {
        guard let step = activeTourStep, let previous = step.previous,
              previous.supportsReturn else { return }
        activeTourStep = previous
        tourResumeStep = previous
    }

    /// The step's outcome happened organically — the user searched, opened a
    /// detail page, or switched the chart period there. Advances past the step
    /// without a bubble interaction; the next stop is offered when its anchor is
    /// next on screen.
    func completeStep(_ step: TourStep) {
        guard tourAvailable else { return }
        if activeTourStep == step { activeTourStep = nil }
        if tourResumeStep == step, let next = step.next { tourResumeStep = next }
    }

    /// Skip and Done both retire the tour permanently.
    func endTour() {
        activeTourStep = nil
        tourResumeStep = .search
        markSeen(.featureTour)
    }

    /// The host went away (window closed, panel dismissed, a page was pushed).
    /// Not a verdict on the tour: it resumes at the same stop next time.
    func pauseTour() {
        guard let step = activeTourStep else { return }
        tourResumeStep = step
        activeTourStep = nil
    }

    private(set) var seenItems: Set<String>
    /// The app version this install first ran with the ledger present. Guidance for
    /// a feature shipped in a later version can target upgraders coming from before it.
    private(set) var firstSeenVersion: String

    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "pulse.onboarding.v1"
    /// The watchlist store persists on its very first load, so this must be read
    /// before `WatchlistStore` is constructed for fresh-install detection to work.
    private static let watchlistKeys = ["pulse.watchlists.v2", "pulse.watchlist.v1"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Debug rehearsal: behave as a fresh install even when the container already
        // holds data, which the grandfathering below would otherwise treat as an upgrade.
        var forceFresh = false
        #if DEBUG
        if CommandLine.arguments.contains("--onboarding-reset") {
            defaults.removeObject(forKey: Self.storageKey)
            forceFresh = true
        }
        #endif
        let currentVersion = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if let data = defaults.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            seenItems = Set(snapshot.seen)
            firstSeenVersion = snapshot.firstSeenVersion
            return
        }
        firstSeenVersion = currentVersion
        let hasExistingData = Self.watchlistKeys.contains { defaults.data(forKey: $0) != nil }
        // An upgrader already lives with the app; replaying the welcome flow at them
        // would read as a regression, not a greeting.
        seenItems = hasExistingData && !forceFresh ? Set(Item.allCases.map(\.rawValue)) : []
        save()
    }

    func hasSeen(_ item: Item) -> Bool {
        seenItems.contains(item.rawValue)
    }

    func markSeen(_ item: Item) {
        guard !hasSeen(item) else { return }
        seenItems.insert(item.rawValue)
        save()
    }

    var shouldPresentWelcomeWindow: Bool { !hasSeen(.welcomeWindow) }

    #if DEBUG
    /// Debug-only: replay every moment as if this were a fresh install.
    func reset() {
        seenItems = []
        welcomeSessionActive = false
        activeTourStep = nil
        tourResumeStep = .search
        save()
    }
    #endif

    private struct Snapshot: Codable {
        var seen: [String]
        var firstSeenVersion: String
    }

    private func save() {
        let snapshot = Snapshot(seen: seenItems.sorted(), firstSeenVersion: firstSeenVersion)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
