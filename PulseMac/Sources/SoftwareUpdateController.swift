import Foundation
import Sparkle

/// Sparkle, plus the one fact the UI wants from it: whether a newer build is
/// known to exist. The popover turns that into a dot on the "more" icon and an
/// "Update to X…" item, so the update is one click from the place users
/// already open, not only reachable from Settings or from an alert they may
/// have dismissed.
///
/// Scheduled checks are shown the gentle way (Sparkle's term): right after
/// launch or when the Mac is idle Sparkle still presents its own alert;
/// otherwise the dot is the only signal, and the alert opens when the user
/// picks the menu item. The dot outlives "Remind me later" on purpose — an
/// update the user has not skipped is still worth a quiet reminder — and
/// clears on skip, on install, or when a check no longer finds it.
@MainActor
final class SoftwareUpdateController: NSObject, ObservableObject {
    static let shared = SoftwareUpdateController()

    struct AvailableUpdate: Equatable {
        /// Marketing version as shown to the user ("0.16.0").
        var displayVersion: String
        /// `CFBundleVersion` of the update, compared numerically to the running build.
        var build: String
    }

    @Published private(set) var isConfigured = false
    @Published private(set) var availableUpdate: AvailableUpdate?
    private var updaterController: SPUStandardUpdaterController?
    private let defaults: UserDefaults

    private static let availableVersionKey = "softwareUpdate.availableVersion"
    private static let availableBuildKey = "softwareUpdate.availableBuild"
    private static let skippedBuildKey = "softwareUpdate.skippedBuild"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var feedURL: String? {
        let value = Bundle.main.infoDictionary?["SUFeedURL"] as? String
        return value?.isEmpty == false ? value : nil
    }

    func start() {
        guard updaterController == nil else { return }
        isConfigured = Self.hasSparkleConfiguration
        guard isConfigured else {
            // A build without a feed can never resolve an update it remembers.
            clearAvailableUpdate()
            return
        }
        availableUpdate = rememberedAvailableUpdate()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    /// Opens Sparkle's alert: a fresh check, or the update a scheduled check
    /// already found and left to the dot.
    func checkForUpdates() {
        start()
        updaterController?.checkForUpdates(nil)
    }

    // MARK: - Remembering the update

    /// The next scheduled check may be a day away, so without this the dot
    /// would vanish on every relaunch. A remembered build the running app
    /// already matches or exceeds means the update was installed; it is dropped.
    private func rememberedAvailableUpdate() -> AvailableUpdate? {
        guard let version = defaults.string(forKey: Self.availableVersionKey),
              let build = defaults.string(forKey: Self.availableBuildKey),
              Self.isNewer(build: build, than: currentBuild) else {
            clearAvailableUpdate()
            return nil
        }
        return AvailableUpdate(displayVersion: version, build: build)
    }

    /// Sparkle only honors "Skip This Version" for scheduled checks; a manual
    /// check shows the skipped build again, and dismissing it would otherwise
    /// bring the dot back for a day. The skipped build is kept here so the
    /// dot stays silent for it until something newer appears.
    private func remember(_ item: SUAppcastItem) {
        let update = AvailableUpdate(displayVersion: item.displayVersionString, build: item.versionString)
        if update.build == defaults.string(forKey: Self.skippedBuildKey) {
            return
        }
        defaults.removeObject(forKey: Self.skippedBuildKey)
        availableUpdate = update
        defaults.set(update.displayVersion, forKey: Self.availableVersionKey)
        defaults.set(update.build, forKey: Self.availableBuildKey)
    }

    private func clearAvailableUpdate() {
        availableUpdate = nil
        defaults.removeObject(forKey: Self.availableVersionKey)
        defaults.removeObject(forKey: Self.availableBuildKey)
    }

    private func skip(_ item: SUAppcastItem) {
        defaults.set(item.versionString, forKey: Self.skippedBuildKey)
        clearAvailableUpdate()
    }

    /// Build numbers are epoch seconds (see `release-mac.sh`), so they compare
    /// as integers; anything else falls back to a numeric string compare.
    private static func isNewer(build: String, than current: String) -> Bool {
        if let lhs = Int(build), let rhs = Int(current) { return lhs > rhs }
        return build.compare(current, options: .numeric) == .orderedDescending
    }

    private static var hasSparkleConfiguration: Bool {
        let info = Bundle.main.infoDictionary
        let feed = info?["SUFeedURL"] as? String
        let publicKey = info?["SUPublicEDKey"] as? String
        return feed?.isEmpty == false && publicKey?.isEmpty == false
    }
}

extension SoftwareUpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        remember(item)
    }

    /// Also how Sparkle reports a version the user skipped: no longer an
    /// update worth a dot.
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        clearAvailableUpdate()
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        switch choice {
        case .skip:
            skip(updateItem)
        case .install:
            clearAvailableUpdate()
        case .dismiss:
            break
        @unknown default:
            break
        }
    }
}

// Unlike `SPUUpdaterDelegate`, this protocol is not declared main-actor in
// Sparkle's headers; Sparkle still calls it on the main thread, so the
// conformance is isolated there rather than marking every method nonisolated.
extension SoftwareUpdateController: @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle proposes immediate focus right after launch or once the Mac
    /// has been idle a while; those alerts are welcome. Any other scheduled
    /// find is ours to surface, and the dot does that.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        remember(update)
    }
}
