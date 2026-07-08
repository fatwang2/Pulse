import SwiftUI
import PulseCore
import PulseUI

struct WatchlistView: View {
    @Environment(AppState.self) private var appState
    @Binding var route: PopoverRoute

    @State private var searchText = ""
    @State private var searchResults: [SymbolInfo] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var refreshHovering = false
    @State private var isReordering = false
    @AppStorage("pulse.watchlist.orderMode.v1") private var listOrderMode = WatchlistOrderMode.manual.rawValue
    @AppStorage("pulse.watchlist.sortOption.v1") private var listSortOption = WatchlistSortOption.changePercent.rawValue

    var body: some View {
        // The correct Liquid Glass structure: put the chrome in safeAreaInset so the system treats it as a floating bar —
        // content scrolls underneath it and fades at the edge via scrollEdgeEffect, without clashing with the chrome text
        Group {
            if !searchText.isEmpty {
                searchList
            } else if appState.watchlist.isEmpty {
                emptyState
            } else {
                watchList
            }
        }
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
                        Label("完成", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .padding(.trailing, 12)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Floating chrome (header + search field)

    private var chrome: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Pulse")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                ClusterMenu(systemName: "ellipsis.circle", help: "更多") {
                    Menu {
                        ForEach(WatchRowMetricMode.allCases, id: \.self) { mode in
                            Toggle(mode.displayName, isOn: metricModeBinding(mode))
                        }
                    } label: {
                        Text("列表显示")
                    }
                    Divider()
                    Menu {
                        Toggle(isReordering ? "正在手动排序" : "手动排序", isOn: orderModeBinding(.manual))

                        Divider()

                        ForEach(WatchlistSortOption.allCases) { option in
                            Toggle(option.title, isOn: sortOptionBinding(option))
                        }
                    } label: {
                        Text("列表排序")
                    }
                    Divider()
                    Button {
                        route = .settings
                    } label: {
                        Text("设置…")
                    }
                    Divider()
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("退出 Pulse")
                    }
                }
                .frame(height: 26)
            }
            searchField
            if searchText.isEmpty && !isReordering {
                portfolioSummary
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    @ViewBuilder
    private var portfolioSummary: some View {
        if let summary = portfolioSummaryData {
            HStack(spacing: 12) {
                summaryItem("今日", value: summary.todayPnL, currencyCode: summary.currencyCode)
                summaryItem("持仓", value: summary.totalPnL, currencyCode: summary.currencyCode)
                Spacer(minLength: 0)
            }
            .padding(.top, 1)
        }
    }

    private func summaryItem(_ label: String, value: Double, currencyCode: String?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(PriceFormatter.moneyMagnitude(value, currencyCode: currencyCode))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(appState.palette.color(for: value))
        }
    }

    private var portfolioSummaryData: (todayPnL: Double, totalPnL: Double, currencyCode: String?)? {
        let rows = positionRows
        let currencyCodes = Set(rows.map(\.currencyCode))
        guard !rows.isEmpty, currencyCodes.count == 1 else { return nil }
        return (
            rows.reduce(0) { $0 + $1.metrics.todayPnL },
            rows.reduce(0) { $0 + $1.metrics.totalPnL },
            currencyCodes.first
        )
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
            return WatchRow.metricColumnWidth(
                priceText: priceText,
                metricText: display.text,
                sessionLabel: sessionLabel
            )
        }
        return widths.max() ?? 52
    }

    private var positionRows: [(metrics: PositionMetrics, currencyCode: String)] {
        appState.watchlist.items.compactMap { item -> (PositionMetrics, String)? in
            guard let quote = appState.market.quote(for: item.symbol) else { return nil }
            guard let metrics = PositionMetrics(item: item, quote: quote) else { return nil }
            return (metrics, quote.currencyCode ?? item.symbol.market.currencyCode)
        }
    }

    /// Status line with the manual-refresh button beside it: freshness info and the action to renew it live together.
    private var footer: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(appState.market.lastError == nil ? Color.green.opacity(0.8) : .orange)
                .frame(width: 6, height: 6)
            Group {
                if isReordering {
                    Text("拖动任意行调整顺序")
                } else if appState.market.lastError != nil {
                    Text("数据源异常，自动降级中")
                } else if let timing = appState.refreshTimingText() {
                    Text(timing)
                } else {
                    Text("加载中…")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Button {
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
            .buttonStyle(.plain)
            .onHover { refreshHovering = $0 }
            .help("立即刷新")
        }
        .frame(height: 22)
        .padding(.leading, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("代码 / 名称 / 拼音，如 AAPL、腾讯、600519", text: $searchText)
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
                .buttonStyle(.plain)
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
            guard !searchText.isEmpty else {
                searchResults = []
                searchError = nil
                return
            }
            isSearching = true
            defer { isSearching = false }
            try? await Task.sleep(for: .milliseconds(300))  // debounce
            guard !Task.isCancelled else { return }
            do {
                searchResults = try await appState.search(searchText)
                searchError = nil
            } catch {
                searchResults = []
                searchError = shortErrorText(error)
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
            if let searchError {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    Text("搜索失败").font(.callout)
                    Text(searchError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if searchResults.isEmpty && !isSearching {
                Text("没有找到匹配的标的")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shortErrorText(_ error: any Error) -> String {
        if let providerError = error as? ProviderError {
            return switch providerError {
            case .network(let detail): "网络不可达：\(detail)"
            case .rateLimited: "数据源暂时受限，约 1 分钟内自动恢复"
            case .clientError(_, let detail): "数据源不支持该查询：\(detail)"
            case .badResponse(let detail): detail
            case .unsupported: "所有数据源都已被禁用，请在设置中开启"
            case .symbolNotFound: "标的不存在"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Watchlist

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34))
                .foregroundStyle(.quaternary)
            Text("搜索添加你的第一只自选")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var watchList: some View {
        let metricColumnWidth = watchRowMetricColumnWidth
        return List {
            ForEach(appState.watchlist.items) { item in
                WatchRow(item: item, metricColumnWidth: metricColumnWidth, isReordering: isReordering) {
                    route = .detail(item.symbol)
                }
                // Inset 4 + the row's internal 8pt padding puts row content on the same 12pt grid as the chrome
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                .listRowSeparator(.hidden)
                .moveDisabled(!isReordering)
                .contextMenu {
                    if !isReordering {
                        Button("设为菜单栏显示") {
                            appState.settings.primarySymbol = item.symbol
                            appState.settings.menuBarMode = .single
                            appState.settings.showPriceInMenuBar = true
                        }
                        Button("编辑持仓") {
                            route = .position(item.symbol, .list)
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            appState.watchlist.remove(item.symbol)
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

    private func enterManualReorderMode() {
        searchText = ""
        withAnimation(.snappy(duration: 0.16)) {
            _ = appState.watchlist.restoreManualOrder()
        }
        listOrderMode = WatchlistOrderMode.manual.rawValue
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
            set: { isSelected in
                guard isSelected else { return }
                switch mode {
                case .manual:
                    enterManualReorderMode()
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
        case .changePercent: "按涨跌幅"
        case .todayPnL: "按今日盈亏"
        case .totalPnL: "按持仓盈亏"
        case .marketValue: "按持仓市值"
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
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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
                    Text(info.symbol.code)
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.secondary)
                    if info.type != .equity {
                        Text(info.type == .etf ? "ETF" : (info.type == .index ? "指数" : "基金"))
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
                .buttonStyle(.plain)
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
}

struct WatchRow: View {
    @Environment(AppState.self) private var appState
    let item: WatchItem
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
                // The name column sizes to its content; all remaining space goes to the sparkline (removes the blank band in the middle)
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(quote?.name ?? item.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        MarketBadge(market: item.symbol.market)
                        Text(item.symbol.code)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .layoutPriority(1)

                SparklineView(
                    values: appState.market.sparklines[item.symbol] ?? [],
                    baseline: quote?.previousClose,
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
                        .contentTransition(.numericText())
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
            .help("点击切换：涨跌幅 / 今日盈亏 / 持仓盈亏")

            if isReordering {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .help("按住拖动调整顺序")
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
            .contentTransition(.numericText())
        .lineLimit(1)
    }

    static func rowMetricDisplay(
        quote: Quote?,
        metrics: PositionMetrics?,
        mode: WatchRowMetricMode,
        item: WatchItem,
        palette: ChangePalette
    ) -> (text: String, color: Color) {
        guard let quote else { return ("…", .secondary) }
        let currencyCode = quote.currencyCode ?? item.symbol.market.currencyCode
        switch mode {
        case .changePercent:
            return (PriceFormatter.percent(quote.changePercent), palette.color(for: quote.change))
        case .todayPnL:
            guard let metrics else {
                return (PriceFormatter.percent(quote.changePercent), palette.color(for: quote.change))
            }
            return (PriceFormatter.signedMoney(metrics.todayPnL, currencyCode: currencyCode),
                    palette.color(for: metrics.todayPnL))
        case .totalPnL:
            guard let metrics else {
                return (PriceFormatter.percent(quote.changePercent), palette.color(for: quote.change))
            }
            return (PriceFormatter.signedMoney(metrics.totalPnL, currencyCode: currencyCode),
                    palette.color(for: metrics.totalPnL))
        case .summary:
            guard let metrics else {
                return (PriceFormatter.percent(quote.changePercent), palette.color(for: quote.change))
            }
            return (PriceFormatter.signedMoney(metrics.totalPnL, currencyCode: currencyCode),
                    palette.color(for: metrics.totalPnL))
        }
    }

    static func metricColumnWidth(priceText: String, metricText: String, sessionLabel: String?) -> CGFloat {
        let priceWidth = CGFloat(priceText.count) * 7.2 + (sessionLabel == nil ? 0 : 21)
        let metricWidth = CGFloat(metricText.count) * 6.6
        return min(max(max(priceWidth, metricWidth), 48), 104)
    }
}
