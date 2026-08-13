import SwiftUI
import PulseCore

/// Settings → Data: move watchlists in and out of Pulse through the clipboard.
///
/// This lives on its own page rather than in the settings list. Import is a
/// multi-step review — paste, read what Pulse understood, then apply — and an
/// entry-by-entry preview inside a settings row would push everything else off
/// the screen every time someone looked at it.
///
/// The two actions name their destination ("to the clipboard", "from the
/// clipboard") because that is what a person has to know to use either one, and
/// the format is taught by a copyable example rather than described in prose.
struct DataSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.pulseHost) private var host
    @Binding var route: PopoverRoute

    private enum Phase: Equatable {
        case idle
        case previewing(WatchlistArchive, WatchlistArchive.ImportPlan)
        case imported(WatchlistArchive.ImportPlan)
        case failed(String)
        case exported(String)
    }

    @State private var phase: Phase = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch phase {
                case .previewing(_, let plan), .imported(let plan):
                    planCard(plan)
                default:
                    actionsCard
                    formatCard
                }
                message
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .animation(.snappy(duration: 0.24), value: phase)
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.backHelp")) {
                route = .settings
            }
            Text(PulseLocalization.localizedString("settings.section.data"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, host == .pinnedWindow ? 2 : 8)
        .padding(.bottom, 8)
    }

    // MARK: - Action bar

    /// Cancel then confirm, right-aligned, small controls — the same action bar the
    /// trade and position pages use. A review step should not invent its own.
    @ViewBuilder
    private var actionBar: some View {
        switch phase {
        case .previewing(let archive, let plan):
            HStack {
                Spacer()
                Button(PulseLocalization.localizedString("action.cancel")) { phase = .idle }
                Button(PulseLocalization.localizedString("data.import.confirm")) {
                    phase = .imported(appState.watchlist.merge(archive))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!plan.changesAnything)
            }
            .controlSize(.small)
            .padding(12)
        case .imported:
            HStack {
                Spacer()
                Button(PulseLocalization.localizedString("action.done")) { phase = .idle }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .padding(12)
        default:
            EmptyView()
        }
    }

    // MARK: - Idle

    private var actionsCard: some View {
        VStack(spacing: 0) {
            actionRow(
                title: "data.export",
                subtitle: "data.export.subtitle",
                systemName: "square.and.arrow.up"
            ) { exportToClipboard() }
            Divider().padding(.leading, 40)
            actionRow(
                title: "data.import",
                subtitle: "data.import.subtitle",
                systemName: "square.and.arrow.down"
            ) { previewClipboard() }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func actionRow(
        title: String,
        subtitle: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(PulseLocalization.localizedString(title))
                        .font(.system(size: 12, weight: .medium))
                    Text(PulseLocalization.localizedString(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// The format, shown rather than described: the shape people actually have to
    /// type, with the copyable example one tap away.
    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PulseLocalization.localizedString("data.format.title"))
                .font(.system(size: 12, weight: .semibold))
            Text(Self.formatSketch)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(PulseLocalization.localizedString("data.format.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(PulseLocalization.localizedString("data.example")) { copyExample() }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private static let formatSketch = """
    {
      "format": "pulse.watchlist", "version": 1,
      "lists": [
        { "name": "…", "entries": [
          { "market": "us", "code": "NVDA" }
        ] }
      ]
    }
    """

    // MARK: - Preview

    /// Every entry, grouped the way the archive groups them, showing the instrument
    /// Pulse resolved rather than the raw text. Seeing `SPX · S&P 500 Index`, or a row
    /// marked unreadable, is the only way to know an import is the one you meant.
    private func planCard(_ plan: WatchlistArchive.ImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(plan.lists) { list in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(list.name)
                            .font(.system(size: 12, weight: .semibold))
                        if list.isNew {
                            Text(PulseLocalization.localizedString("data.import.newList"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(list.items) { item in
                        HStack(spacing: 6) {
                            Text(identity(of: item))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(item.symbol == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(PulseLocalization.localizedString(statusKey(for: item.outcome)))
                                .font(.caption)
                                .foregroundStyle(statusColor(for: item.outcome))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var message: some View {
        switch phase {
        case .failed(let text):
            note(text, color: .orange)
        case .exported(let text):
            note(text, color: .green)
        case .previewing(_, let plan):
            note(planSummary(for: plan), color: plan.skippedCount > 0 ? .orange : .secondary)
        case .imported(let plan):
            note(
                PulseLocalization.localizedString("data.import.done", plan.addCount, plan.newListCount),
                color: plan.changesAnything ? .green : .secondary
            )
        case .idle:
            EmptyView()
        }
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func exportToClipboard() {
        let archive = appState.watchlist.archive(app: appVersion)
        do {
            try ClipboardTextExporter.write(archive.encoded())
            let symbols = archive.lists.reduce(0) { $0 + $1.entries.count }
            phase = .exported(PulseLocalization.localizedString(
                "data.export.done", archive.lists.count, symbols
            ))
        } catch {
            phase = .failed(PulseLocalization.localizedString("share.text.copyFailed"))
        }
    }

    private func copyExample() {
        do {
            try ClipboardTextExporter.write(WatchlistArchive.example().encoded())
            phase = .exported(PulseLocalization.localizedString("data.example.done"))
        } catch {
            phase = .failed(PulseLocalization.localizedString("share.text.copyFailed"))
        }
    }

    private func previewClipboard() {
        guard let text = ClipboardTextReader.read() else {
            phase = .failed(PulseLocalization.localizedString("data.error.emptyClipboard"))
            return
        }
        do {
            let archive = try WatchlistArchive.decoded(from: text)
            phase = .previewing(archive, appState.watchlist.importPlan(for: archive))
        } catch let failure as WatchlistArchive.DecodingFailure {
            phase = .failed(message(for: failure))
        } catch {
            phase = .failed(PulseLocalization.localizedString("data.error.notArchive"))
        }
    }

    // MARK: - Copy

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return version.map { "Pulse \($0)" } ?? "Pulse"
    }

    /// `US · NVDA` for a plain security, plus the resolved identity when Pulse read the
    /// code as something structured (an index alias, a crypto pair).
    private func identity(of item: WatchlistArchive.ImportPlan.Item) -> String {
        guard let symbol = item.symbol else {
            // An unreadable entry still echoes what was written, but a blank code
            // must not render as a dangling separator.
            let market = item.entry.market.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = item.entry.code.trimmingCharacters(in: .whitespacesAndNewlines)
            return [market, code].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let base = "\(symbol.market.displayName) · \(symbol.displayCode)"
        if let index = symbol.indexID {
            return "\(base) · \(index.displayName)"
        }
        if let name = item.entry.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty, name != symbol.displayCode {
            return "\(base) · \(name)"
        }
        return base
    }

    private func statusKey(for outcome: WatchlistArchive.ImportPlan.Outcome) -> String {
        switch outcome {
        case .add: "data.import.status.add"
        case .alreadyInList: "data.import.status.present"
        case .restorePosition: "data.import.status.position"
        case .skipped(.unknownMarket): "data.import.status.unknownMarket"
        case .skipped(.missingCode): "data.import.status.missingCode"
        case .skipped: "data.import.status.unreadable"
        }
    }

    private func statusColor(for outcome: WatchlistArchive.ImportPlan.Outcome) -> Color {
        switch outcome {
        case .add, .restorePosition: .green
        case .alreadyInList: .secondary
        case .skipped: .orange
        }
    }

    private func planSummary(for plan: WatchlistArchive.ImportPlan) -> String {
        guard plan.skippedCount == 0 else {
            return PulseLocalization.localizedString("data.import.someUnreadable", plan.skippedCount)
        }
        guard plan.changesAnything else {
            return PulseLocalization.localizedString("data.import.unchanged")
        }
        return PulseLocalization.localizedString(
            "data.import.willAdd", plan.addCount, plan.newListCount
        )
    }

    private func message(for failure: WatchlistArchive.DecodingFailure) -> String {
        switch failure {
        case .notJSON, .wrongFormat:
            PulseLocalization.localizedString("data.error.notArchive")
        case .unsupportedVersion:
            PulseLocalization.localizedString("data.error.newerVersion")
        case .noLists:
            PulseLocalization.localizedString("data.error.noLists")
        }
    }
}
