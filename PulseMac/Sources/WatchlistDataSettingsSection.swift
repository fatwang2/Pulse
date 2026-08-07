import SwiftUI
import PulseCore

/// Settings → Watchlist Data: copy a portable backup, or merge one back in.
///
/// Both directions go through the clipboard rather than a file panel. Pulse lives in a
/// menu bar popover that a modal `NSOpenPanel` would dismiss out from under the user,
/// and the app already treats the pasteboard as its export surface ("Copy as Image",
/// "Copy as Text"), so this stays inside a pattern people have already met — and it
/// needs no file-access entitlement.
struct WatchlistDataSettingsSection: View {
    @Environment(AppState.self) private var appState

    /// Import is a two-step: parse and describe what would happen, then apply. The merge
    /// itself never deletes anything, but a pasteboard is easy to be wrong about, so the
    /// user gets to see the shape of the payload before it lands.
    private enum ImportState: Equatable {
        case idle
        case pending(WatchlistArchive)
        case failed(String)
        case done(WatchlistArchive.MergeReport)
    }

    @State private var importState: ImportState = .idle
    @State private var exportMessage: String?

    var body: some View {
        Section {
            Button(PulseLocalization.localizedString("settings.data.export")) {
                copyBackup()
            }

            switch importState {
            case .pending(let archive):
                LabeledContent(
                    PulseLocalization.localizedString("settings.data.importPending"),
                    value: summary(of: archive)
                )
                HStack {
                    Button(PulseLocalization.localizedString("settings.data.importConfirm")) {
                        apply(archive)
                    }
                    Button(PulseLocalization.localizedString("action.cancel")) {
                        importState = .idle
                    }
                }
            default:
                Button(PulseLocalization.localizedString("settings.data.import")) {
                    readClipboard()
                }
            }
        } header: {
            Text(PulseLocalization.localizedString("settings.section.watchlistData"))
        } footer: {
            footer
        }
        .animation(.snappy(duration: 0.22), value: importState)
    }

    @ViewBuilder
    private var footer: some View {
        switch importState {
        case .failed(let message):
            Text(message).foregroundStyle(.orange)
        case .done(let report):
            Text(resultText(for: report)).foregroundStyle(report.changedAnything ? .green : .secondary)
        default:
            if let exportMessage {
                Text(exportMessage).foregroundStyle(.green)
            } else {
                Text(PulseLocalization.localizedString("settings.data.help"))
            }
        }
    }

    // MARK: - Actions

    private func copyBackup() {
        importState = .idle
        let archive = appState.watchlist.archive(app: appVersion)
        do {
            try ClipboardTextExporter.write(archive.encoded())
            exportMessage = PulseLocalization.localizedString("settings.data.exported")
        } catch {
            exportMessage = nil
            importState = .failed(PulseLocalization.localizedString("share.text.copyFailed"))
        }
    }

    private func readClipboard() {
        exportMessage = nil
        guard let text = ClipboardTextReader.read() else {
            importState = .failed(PulseLocalization.localizedString("settings.data.error.emptyClipboard"))
            return
        }
        do {
            importState = .pending(try WatchlistArchive.decoded(from: text))
        } catch let failure as WatchlistArchive.DecodingFailure {
            importState = .failed(message(for: failure))
        } catch {
            importState = .failed(PulseLocalization.localizedString("settings.data.error.notArchive"))
        }
    }

    private func apply(_ archive: WatchlistArchive) {
        importState = .done(appState.watchlist.merge(archive))
    }

    // MARK: - Copy

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return version.map { "Pulse \($0)" } ?? "Pulse"
    }

    private func summary(of archive: WatchlistArchive) -> String {
        PulseLocalization.localizedString(
            "settings.data.importSummary",
            archive.lists.count,
            archive.lists.reduce(0) { $0 + $1.entries.count }
        )
    }

    private func resultText(for report: WatchlistArchive.MergeReport) -> String {
        guard report.changedAnything else {
            return PulseLocalization.localizedString("settings.data.importUnchanged")
        }
        return PulseLocalization.localizedString(
            "settings.data.importDone",
            report.symbolsAdded,
            report.listsCreated
        )
    }

    private func message(for failure: WatchlistArchive.DecodingFailure) -> String {
        switch failure {
        case .notJSON, .wrongFormat:
            PulseLocalization.localizedString("settings.data.error.notArchive")
        case .unsupportedVersion:
            PulseLocalization.localizedString("settings.data.error.newerVersion")
        case .noLists:
            PulseLocalization.localizedString("settings.data.error.noLists")
        }
    }
}
