import SwiftUI
import PulseCore
import PulseUI

struct WatchlistView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var route: PopoverRoute

    @State private var searchText = ""
    @State private var searchResults: [SymbolInfo] = []
    @State private var searchCache: [String: [SymbolInfo]] = [:]
    @State private var completedSearchQuery: String?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var refreshHovering = false
    @State private var isReordering = false
    @State private var shareFeedback: ShareFeedback?
    @AppStorage("pulse.watchlist.orderMode.v1") private var listOrderMode = WatchlistOrderMode.manual.rawValue
    @AppStorage("pulse.watchlist.sortOption.v1") private var listSortOption = WatchlistSortOption.changePercent.rawValue

    var body: some View {
        // The correct Liquid Glass structure: put the chrome in safeAreaInset so the system treats it as a floating bar —
        // content scrolls underneath it and fades at the edge via scrollEdgeEffect, without clashing with the chrome text
        ZStack {
            baseContent
                .opacity(searchText.isEmpty ? 1 : 0)
                .allowsHitTesting(searchText.isEmpty)
            searchList
                .opacity(searchText.isEmpty ? 0 : 1)
                .allowsHitTesting(!searchText.isEmpty)
        }
        // Crossfade the watchlist ↔ search swap; it only fires at the empty ↔
        // non-empty boundary, so typing stays instant after the first character.
        .animation(.easeOut(duration: 0.15), value: searchText.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaInset(edge: .top, spacing: 0) { chrome }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                footer
                Spacer()
                if isReordering {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { isReordering = false }
                    } label: {
                        Label(PulseLocalization.localizedString("action.done"), systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .padding(.trailing, 12)
                    .padding(.bottom, 4)
                }
            }
            .opacity(searchText.isEmpty ? 1 : 0)
            .allowsHitTesting(searchText.isEmpty)
        }
    }

    @ViewBuilder
    private var baseContent: some View {
        if appState.watchlist.isEmpty {
            emptyState
        } else {
            watchList
        }
    }

    // MARK: - Floating chrome (header + search field)

    private var chrome: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                // Bundle display name: "Pulse Dev" in Debug builds, "Pulse" in Release
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Pulse")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                ClusterIcon(
                    systemName: "square.and.arrow.up",
                    help: PulseLocalization.localizedString("action.copyShareSnapshot")
                ) {
                    copyShareSnapshot()
                }
                .disabled(appState.watchlist.isEmpty)
                .opacity(appState.watchlist.isEmpty ? 0.45 : 1)
                ClusterMenu(systemName: "ellipsis.circle", help: PulseLocalization.localizedString("action.more")) {
                    Menu {
                        ForEach(WatchRowMetricMode.allCases, id: \.self) { mode in
                            Toggle(mode.displayName, isOn: metricModeBinding(mode))
                        }
                    } label: {
                        Text(PulseLocalization.localizedString("watchlist.menu.display"))
                    }
                    Divider()
                    Menu {
                        // State group: where the current order comes from (checkmark semantics).
                        Toggle(
                            PulseLocalization.localizedString("watchlist.sort.manual"),
                            isOn: orderModeBinding(.manual)
                        )

                        Divider()

                        ForEach(WatchlistSortOption.allCases) { option in
                            Toggle(option.title, isOn: sortOptionBinding(option))
                        }

                        Divider()

                        // Action: enter the drag-to-reorder state for the arrangement on screen.
                        Button {
                            beginAdjustingOrder()
                        } label: {
                            Text(PulseLocalization.localizedString(
                                isReordering ? "watchlist.sort.adjustActive" : "watchlist.sort.adjust"
                            ))
                        }
                        .disabled(isReordering)
                    } label: {
                        Text(PulseLocalization.localizedString("watchlist.menu.sort"))
                    }
                    Divider()
                    Button {
                        route = .settings
                    } label: {
                        Text(PulseLocalization.localizedString("settings.title"))
                    }
                    Divider()
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text(PulseLocalization.localizedString("action.quitPulse"))
                    }
                }
                .frame(height: 26)
            }
            .overlay(alignment: .trailing) {
                if let shareFeedback {
                    ShareFeedbackHUD(feedback: shareFeedback)
                        .padding(.trailing, 62)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                        .allowsHitTesting(false)
                }
            }
            searchField
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    private var watchRowMetricColumnWidth: CGFloat {
        let mode = appState.settings.watchRowMetricMode
        let widths = appState.watchlist.items.map { item -> CGFloat in
            let quote = appState.market.quote(for: item.symbol)
            let metrics = quote.flatMap { PositionMetrics(item: item, quote: $0) }
            let display = WatchRow.rowMetricDisplay(
                quote: quote,
                metrics: metrics,
                mode: mode,
                item: item,
                palette: appState.palette
            )
            let priceText = quote.map { PriceFormatter.price($0.price) } ?? "—"
            let sessionLabel = quote?.marketState?.extendedSessionLabel
            return WatchRowColumnLayout.metricWidth(
                priceText: priceText,
                metricText: display.text,
                sessionLabel: sessionLabel,
                presentation: .popover
            )
        }
        return widths.max() ?? 52
    }

    private var watchRowTitleColumnWidth: CGFloat {
        let widths = appState.watchlist.items.map { item in
            WatchRowColumnLayout.titleWidth(
                name: appState.market.quote(for: item.symbol)?.name ?? item.displayName,
                symbolCode: item.symbol.displayCode,
                marketName: item.symbol.market.displayName,
                presentation: .popover
            )
        }
        return widths.max() ?? 48
    }

    /// Health line with the manual-refresh button beside it. With per-provider cadences and
    /// push updates there is no single "refreshed at" moment anymore, so the line carries
    /// health only: a status dot, plus the fallback notice when a source is failing.
    private var footer: some View {
        HStack(spacing: 5) {
            if isReordering {
                Text(PulseLocalization.localizedString("status.reorderHint"))
            } else {
                Circle()
                    .fill(appState.market.lastError == nil ? Color.green.opacity(0.8) : .orange)
                    .frame(width: 6, height: 6)
                if appState.market.lastError != nil {
                    Text(PulseLocalization.localizedString("status.providerFallback"))
                } else if appState.liveStreaming {
                    Text(PulseLocalization.localizedString("status.streaming"))
                } else {
                    Text(PulseLocalization.localizedString("status.healthy"))
                }
                Button {
                    PulseTelemetry.signal(.manualRefreshRequested)
                    appState.engine.poke()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(refreshHovering ? .primary : .secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(refreshHovering ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.pressable)
                .onHover { refreshHovering = $0 }
                .help(PulseLocalization.localizedString("action.refreshNow"))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(height: 22)
        .padding(.leading, 12)
        .padding(.bottom, 4)
    }

    @MainActor
    private func copyShareSnapshot() {
        do {
            let snapshot = WatchlistShareSnapshot(appState: appState)
            let card = PulseShareCard(
                metadata: PulseShareCardMetadata(updatedAtText: snapshot.updatedAtText)
            ) {
                WatchlistShareContent(snapshot: snapshot)
            }
            let artifact = try ShareImageRenderer.render(
                card,
                configuration: .socialPortrait(
                    height: snapshot.preferredImageHeight,
                    colorScheme: colorScheme,
                    locale: appState.settings.locale
                )
            )
            try ClipboardImageExporter.write(artifact)
            showShareFeedback(isSuccess: true)
        } catch {
            showShareFeedback(isSuccess: false)
        }
    }

    @MainActor
    private func showShareFeedback(isSuccess: Bool) {
        let feedback = ShareFeedback(isSuccess: isSuccess)
        withAnimation(.snappy(duration: 0.2)) {
            shareFeedback = feedback
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(isSuccess ? 1.5 : 3))
            guard shareFeedback?.id == feedback.id else { return }
            withAnimation(.snappy(duration: 0.2)) {
                shareFeedback = nil
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(PulseLocalization.localizedString("search.placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if isSearching {
                ProgressView().controlSize(.mini)
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 0.5)
        }
        .disabled(isReordering)
        .opacity(isReordering ? 0.45 : 1)
        .task(id: searchText) {
            let query = normalizedSearchQuery(searchText)
            guard shouldRunSearch(for: query) else {
                searchResults = []
                searchError = nil
                completedSearchQuery = nil
                return
            }
            if let cached = searchCache[query] {
                searchResults = cached
                searchError = nil
                completedSearchQuery = query
                return
            }
            isSearching = true
            searchResults = []
            searchError = nil
            completedSearchQuery = nil
            defer { isSearching = false }
            try? await Task.sleep(for: .milliseconds(800))  // debounce
            guard !Task.isCancelled else { return }
            do {
                let results = try await appState.search(query)
                searchCache[query] = results
                searchResults = results
                searchError = nil
                completedSearchQuery = query
            } catch {
                searchResults = []
                searchError = shortErrorText(error)
                completedSearchQuery = query
            }
        }
    }

    private var searchList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(searchResults) { info in
                    SearchResultRow(info: info) {
                        appState.watchlist.add(info)
                        appState.engine.poke()
                        searchText = ""
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .overlay {
            let query = normalizedSearchQuery(searchText)
            let completedCurrentSearch = completedSearchQuery == query
            if let searchError, completedCurrentSearch {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    Text(PulseLocalization.localizedString("search.failed")).font(.callout)
                    Text(searchError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if searchResults.isEmpty && completedCurrentSearch && shouldRunSearch(for: query) {
                Text(PulseLocalization.localizedString("search.noResults"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func normalizedSearchQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldRunSearch(for query: String) -> Bool {
        query.count >= 2
    }

    private func shortErrorText(_ error: any Error) -> String {
        if let providerError = error as? ProviderError {
            return switch providerError {
            case .network(let detail): PulseLocalization.localizedString("error.network", detail)
            case .rateLimited: PulseLocalization.localizedString("error.rateLimited")
            case .clientError(_, let detail): PulseLocalization.localizedString("error.client", detail)
            case .badResponse(let detail): detail
            case .unsupported: PulseLocalization.localizedString("error.unsupported")
            case .symbolNotFound: PulseLocalization.localizedString("error.symbolNotFound")
            }
        }
        return error.localizedDescription
    }

    // MARK: - Watchlist

    @State private var emptyStateShown = false

    /// First-run is the one rare moment that earns an entrance: icon and text
    /// fade up with a short stagger. Reduced motion drops the offset, keeps the fade.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34))
                .foregroundStyle(.quaternary)
                .opacity(emptyStateShown ? 1 : 0)
                .offset(y: emptyStateShown || reduceMotion ? 0 : 6)
                .animation(.snappy(duration: 0.35), value: emptyStateShown)
            Text(PulseLocalization.localizedString("empty.watchlist"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(emptyStateShown ? 1 : 0)
                .offset(y: emptyStateShown || reduceMotion ? 0 : 6)
                .animation(.snappy(duration: 0.35).delay(0.06), value: emptyStateShown)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { emptyStateShown = true }
        .onDisappear { emptyStateShown = false }
    }

    private var watchList: some View {
        let titleColumnWidth = watchRowTitleColumnWidth
        let metricColumnWidth = watchRowMetricColumnWidth
        return List {
            ForEach(appState.watchlist.items) { item in
                WatchRow(
                    item: item,
                    titleColumnWidth: titleColumnWidth,
                    metricColumnWidth: metricColumnWidth,
                    isReordering: isReordering
                ) {
                    route = .detail(item.symbol)
                }
                // Inset 4 + the row's internal 8pt padding puts row content on the same 12pt grid as the chrome
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                .listRowSeparator(.hidden)
                .moveDisabled(!isReordering)
                .contextMenu {
                    if !isReordering {
                        Button(PulseLocalization.localizedString("action.pinToMenuBar")) {
                            appState.settings.primarySymbol = item.symbol
                            appState.settings.menuBarMode = .single
                            appState.settings.showPriceInMenuBar = true
                        }
                        Button(PulseLocalization.localizedString("action.editPosition")) {
                            route = .position(item.symbol, .list)
                        }
                        Divider()
                        Button(PulseLocalization.localizedString("action.delete"), role: .destructive) {
                            withAnimation(.snappy(duration: 0.22)) {
                                appState.watchlist.remove(item.symbol)
                            }
                        }
                    }
                }
            }
            .onMove { source, destination in
                appState.watchlist.move(fromOffsets: source, toOffset: destination)
                appState.watchlist.rememberManualOrder()
                listOrderMode = WatchlistOrderMode.manual.rawValue
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// State switch: bring back the remembered custom order. Does not enter the reorder UI.
    private func selectCustomOrder() {
        searchText = ""
        withAnimation(.snappy(duration: 0.16)) {
            _ = appState.watchlist.restoreManualOrder()
        }
        listOrderMode = WatchlistOrderMode.manual.rawValue
    }

    /// Action: start adjusting the arrangement currently on screen. Order mode and the remembered
    /// custom order stay untouched until the first actual drag (onMove commits both), so exiting
    /// without dragging changes nothing.
    private func beginAdjustingOrder() {
        searchText = ""
        withAnimation(.snappy(duration: 0.25)) { isReordering = true }
    }

    private func applySort(_ option: WatchlistSortOption) {
        if listOrderMode == WatchlistOrderMode.manual.rawValue {
            appState.watchlist.rememberManualOrder()
        }

        let sortedSymbols = appState.watchlist.items
            .enumerated()
            .sorted { lhs, rhs in
                let left = sortValue(for: lhs.element, option: option)
                let right = sortValue(for: rhs.element, option: option)

                switch (left, right) {
                case let (left?, right?):
                    if left == right { return lhs.offset < rhs.offset }
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map { $0.element.symbol }

        searchText = ""
        isReordering = false
        listOrderMode = WatchlistOrderMode.automatic.rawValue
        listSortOption = option.rawValue
        withAnimation(.snappy(duration: 0.16)) {
            appState.watchlist.reorder(sortedSymbols)
        }
    }

    private func metricModeBinding(_ mode: WatchRowMetricMode) -> Binding<Bool> {
        Binding(
            get: { appState.settings.watchRowMetricMode == mode },
            set: { isSelected in
                guard isSelected else { return }
                appState.settings.watchRowMetricMode = mode
            }
        )
    }

    private func orderModeBinding(_ mode: WatchlistOrderMode) -> Binding<Bool> {
        Binding(
            get: { listOrderMode == mode.rawValue },
            // Menu radio semantics: selecting an item always fires, even when already checked
            // (a checked Toggle sends `false` on click). Restoring is idempotent, so this is safe.
            set: { _ in
                switch mode {
                case .manual:
                    selectCustomOrder()
                case .automatic:
                    break
                }
            }
        )
    }

    private func sortOptionBinding(_ option: WatchlistSortOption) -> Binding<Bool> {
        Binding(
            get: {
                listOrderMode == WatchlistOrderMode.automatic.rawValue
                    && listSortOption == option.rawValue
            },
            set: { isSelected in
                guard isSelected else { return }
                applySort(option)
            }
        )
    }

    private func sortValue(for item: WatchItem, option: WatchlistSortOption) -> Double? {
        guard let quote = appState.market.quote(for: item.symbol) else { return nil }
        let metrics = PositionMetrics(item: item, quote: quote)
        switch option {
        case .changePercent:
            return quote.changePercent
        case .todayPnL:
            return metrics?.todayPnL
        case .totalPnL:
            return metrics?.totalPnL
        case .marketValue:
            return metrics?.marketValue
        }
    }
}

// MARK: - Components

private enum WatchlistOrderMode: String {
    case manual
    case automatic
}

private enum WatchlistSortOption: String, CaseIterable, Identifiable {
    case changePercent
    case todayPnL
    case totalPnL
    case marketValue

    var id: Self { self }

    var title: String {
        switch self {
        case .changePercent: PulseLocalization.localizedString("sort.changePercent")
        case .todayPnL: PulseLocalization.localizedString("sort.todayPnL")
        case .totalPnL: PulseLocalization.localizedString("sort.totalPnL")
        case .marketValue: PulseLocalization.localizedString("sort.marketValue")
        }
    }
}

/// Compact icon button for popover chrome.
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Menu variant of `ClusterIcon`: same compact chrome look, but opens a menu instead of firing an action.
struct ClusterMenu<Content: View>: View {
    let systemName: String
    let help: String
    @ViewBuilder let content: Content
    @State private var hovering = false

    init(systemName: String, help: String, @ViewBuilder content: () -> Content) {
        self.systemName = systemName
        self.help = help
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Small icon button for dense menu-bar popover chrome.
struct ClusterIcon: View {
    let systemName: String
    let help: String
    var isActive: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : (hovering ? .primary : .secondary))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.12)
                              : (hovering ? Color.primary.opacity(0.08) : .clear))
                )
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct SearchResultRow: View {
    @Environment(AppState.self) private var appState
    let info: SymbolInfo
    let onAdd: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    MarketBadge(market: info.symbol.market)
                    Text(info.symbol.displayCode)
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.secondary)
                    if let typeLabel {
                        Text(typeLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            if appState.watchlist.contains(info.symbol) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hovering ? Color.primary.opacity(0.05) : .clear)
        )
        .onHover { hovering = $0 }
    }

    private var typeLabel: String? {
        switch info.type {
        case .equity, .crypto:
            nil
        case .etf:
            "ETF"
        case .index:
            PulseLocalization.localizedString("assetType.index")
        case .fund:
            PulseLocalization.localizedString("assetType.fund")
        case .other:
            nil
        }
    }
}

struct WatchRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: WatchItem
    let titleColumnWidth: CGFloat
    let metricColumnWidth: CGFloat
    var isReordering: Bool = false
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        let quote = appState.market.quote(for: item.symbol)
        let change = quote?.change ?? 0
        let color = appState.palette.color(for: change)
        let metrics = quote.flatMap { PositionMetrics(item: item, quote: $0) }
        let metricMode = appState.settings.watchRowMetricMode
        let metricDisplay = Self.rowMetricDisplay(
            quote: quote,
            metrics: metrics,
            mode: metricMode,
            item: item,
            palette: appState.palette
        )
        let priceText = quote.map { PriceFormatter.price($0.price) } ?? "—"
        let sessionLabel = quote?.marketState?.extendedSessionLabel

        // In manual sort mode, row tap gestures are fully detached so List's reorder drag can own mousedown.
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                // The list's widest required title establishes one shared column; the aligned remainder goes to every sparkline.
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(quote?.name ?? item.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        MarketBadge(market: item.symbol.market)
                        Text(item.symbol.displayCode)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: titleColumnWidth, alignment: .leading)

                IntradaySparklineView(
                    candles: appState.market.sparklines[item.symbol] ?? [],
                    previousClose: quote?.previousClose,
                    market: item.symbol.market,
                    tint: color
                )
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
            }
            .contentShape(Rectangle())
            .gesture(TapGesture().onEnded { onOpen() }, isEnabled: !isReordering)

            VStack(alignment: .trailing, spacing: 2.5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let sessionLabel {
                        Text(sessionLabel)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Text(priceText)
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)
                        // numericText(value:) rolls digits up on an uptick and down on a downtick;
                        // the scoped .animation supplies the transaction that quote refreshes lack.
                        .contentTransition(reduceMotion ? .opacity : .numericText(value: quote?.price ?? 0))
                        .animation(.snappy(duration: 0.25), value: priceText)
                }
                rowMetricView(display: metricDisplay)
            }
            .frame(width: metricColumnWidth, alignment: .trailing)
            .layoutPriority(2)
            .contentShape(Rectangle())
            // Fast path for switching the metric column (THS-style): tap the numbers to cycle.
            // The open-detail tap is scoped to the name/sparkline group, so the two never double-fire.
            .gesture(TapGesture().onEnded {
                appState.settings.watchRowMetricMode = appState.settings.watchRowMetricMode.next
            }, isEnabled: !isReordering)
            .help(PulseLocalization.localizedString("watchRow.metricHelp"))

            if isReordering {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .help(PulseLocalization.localizedString("watchRow.dragHelp"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hovering || isReordering ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func rowMetricView(quote: Quote?, metrics: PositionMetrics?, mode: WatchRowMetricMode) -> some View {
        let display = Self.rowMetricDisplay(
            quote: quote,
            metrics: metrics,
            mode: mode,
            item: item,
            palette: appState.palette
        )
        rowMetricView(display: display)
    }

    @ViewBuilder
    private func rowMetricView(display: (text: String, color: Color)) -> some View {
        Text(display.text)
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(display.color)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .allowsTightening(true)
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(.snappy(duration: 0.25), value: display.text)
    }

    static func rowMetricDisplay(
        quote: Quote?,
        metrics: PositionMetrics?,
        mode: WatchRowMetricMode,
        item: WatchItem,
        palette: ChangePalette
    ) -> (text: String, color: Color) {
        let display = WatchRowMetricDisplay.resolve(
            quote: quote,
            metrics: metrics,
            mode: mode,
            item: item
        )
        return (
            display.text,
            display.colorValue.map(palette.color(for:)) ?? .secondary
        )
    }

}
