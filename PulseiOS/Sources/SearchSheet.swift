import SwiftUI
import PulseCore
import PulseUI

/// Market search: type, pick, and either add to the watchlist in place or open
/// the instrument page. Results come from the same CompositeProvider routing
/// the Mac popover search uses.
struct SearchSheet: View {
    @Environment(IOSAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Called when the user opens a result's detail page; the host closes the
    /// sheet and pushes the destination.
    let openSymbol: (SymbolID) -> Void

    @State private var query = ""
    @State private var results: [SymbolInfo] = []
    @State private var isSearching = false
    @State private var searchFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    emptyContent
                } else {
                    resultList
                }
            }
            .navigationTitle(PulseLocalization.localizedString("action.search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label(
                            PulseLocalization.localizedString("action.close"),
                            systemImage: "xmark"
                        )
                    }
                }
            }
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: PulseLocalization.localizedString("search.placeholder")
        )
        .task(id: query) {
            await runSearch()
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            searchFailed = false
            return
        }
        // Debounce: typing cancels the previous round before it fires.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await appState.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            searchFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchFailed = true
        }
    }

    private var resultList: some View {
        List(results) { info in
            Button {
                openSymbol(info.symbol)
            } label: {
                resultRow(info)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func resultRow(_ info: SymbolInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(info.resolvedDisplayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    MarketBadge(market: info.symbol.market)
                    Text(info.symbol.displayCode)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            addButton(info)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func addButton(_ info: SymbolInfo) -> some View {
        let isWatched = appState.watchlist.contains(info.symbol)
        Button {
            if isWatched {
                appState.watchlist.remove(info.symbol)
            } else {
                appState.watchlist.add(info)
            }
            appState.watchlistSymbolsChanged()
        } label: {
            Image(systemName: isWatched ? "checkmark.circle.fill" : "plus.circle")
                .font(.title3)
                .foregroundStyle(isWatched ? Color.green : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
    }

    private var emptyContent: some View {
        Group {
            if isSearching {
                ProgressView()
            } else if searchFailed {
                ContentUnavailableView {
                    Label(
                        PulseLocalization.localizedString("search.failed"),
                        systemImage: "wifi.exclamationmark"
                    )
                }
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ContentUnavailableView {
                    Label(
                        PulseLocalization.localizedString("action.search"),
                        systemImage: "magnifyingglass"
                    )
                } description: {
                    Text(PulseLocalization.localizedString("empty.watchlist"))
                }
            }
        }
    }
}
