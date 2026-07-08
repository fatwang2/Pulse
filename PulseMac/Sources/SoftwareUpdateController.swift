import Foundation
import Sparkle

@MainActor
final class SoftwareUpdateController: NSObject, ObservableObject {
    static let shared = SoftwareUpdateController()

    @Published private(set) var isConfigured = false
    private var updaterController: SPUStandardUpdaterController?

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
        guard isConfigured else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        start()
        updaterController?.checkForUpdates(nil)
    }

    private static var hasSparkleConfiguration: Bool {
        let info = Bundle.main.infoDictionary
        let feed = info?["SUFeedURL"] as? String
        let publicKey = info?["SUPublicEDKey"] as? String
        return feed?.isEmpty == false && publicKey?.isEmpty == false
    }
}
