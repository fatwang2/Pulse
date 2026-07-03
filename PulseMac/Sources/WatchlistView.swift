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
    @State private var isReordering = false

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
                    .padding(.bottom, 10)
                }
            }
        }
    }

    // MARK: - Floating chrome (header + search field)

    private var chrome: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                // The title just floats over the content, no glass (the scroll edge effect keeps it readable)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Pulse")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                // Standard Liquid Glass idiom: a group of tool buttons shares one glass capsule (instead of separate rings)
                HStack(spacing: 2) {
                    if appState.watchlist.items.count > 1 {
                        ClusterIcon(systemName: "arrow.up.arrow.down", help: "调整顺序",
                                    isActive: isReordering) {
                            searchText = ""
                            withAnimation(.snappy(duration: 0.25)) { isReordering.toggle() }
                        }
                    }
                    ClusterIcon(systemName: "arrow.clockwise", help: "立即刷新") {
                        appState.engine.poke()
                    }
                    ClusterIcon(systemName: "gearshape", help: "设置") {
                        route = .settings
                    }
                    ClusterIcon(systemName: "power", help: "退出 Pulse") {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding(.horizontal, 4)
                .frame(height: 28)
                .glassEffect(.regular, in: Capsule())
            }
            searchField
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(appState.market.lastError == nil ? Color.green.opacity(0.8) : .orange)
                .frame(width: 6, height: 6)
            Group {
                if isReordering {
                    Text("按住任意行拖动调整顺序")
                } else if appState.market.lastError != nil {
                    Text("数据源异常，自动降级中")
                } else if let refreshed = appState.market.lastRefresh {
                    Text("更新于 \(refreshed.formatted(date: .omitted, time: .standard))")
                } else {
                    Text("加载中…")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .glassEffect()
        .padding(.leading, 12)
        .padding(.bottom, 10)
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
        .frame(height: 28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9))
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
            .padding(.horizontal, 6)
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
            Text("支持美股 · 港股 · A 股 · ETF · 指数")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var watchList: some View {
        List {
            ForEach(appState.watchlist.items) { item in
                WatchRow(item: item, isReordering: isReordering) {
                    route = .detail(item.symbol)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button("设为菜单栏显示") {
                        appState.settings.primarySymbol = item.symbol
                        appState.settings.menuBarMode = .single
                        appState.settings.showPriceInMenuBar = true
                    }
                    Divider()
                    Button("删除", role: .destructive) {
                        appState.watchlist.remove(item.symbol)
                    }
                }
            }
            .onMove { source, destination in
                appState.watchlist.move(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Components

/// Standalone single glass round button (back button on detail/settings pages)
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help(help)
    }
}

/// Icon button inside the shared glass capsule: a highlight appears within the capsule on hover; isActive marks the corresponding mode as on
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
                .frame(width: 26, height: 22)
                .background(
                    Capsule().fill(isActive ? Color.accentColor.opacity(0.14)
                                            : (hovering ? Color.primary.opacity(0.09) : .clear))
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
        HStack(spacing: 8) {
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
    var isReordering: Bool = false
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        let quote = appState.market.quote(for: item.symbol)
        let change = quote?.change ?? 0
        let color = appState.palette.color(for: change)

        // Note: don't wrap the whole row in a Button — the button swallows mousedown, so List's drag-to-reorder (onMove) can never start.
        // Use contentShape + onTapGesture instead: tap opens the detail, press-and-drag is left to List for reordering.
        HStack(spacing: 12) {
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
            .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)

            VStack(alignment: .trailing, spacing: 2.5) {
                Text(quote.map { PriceFormatter.price($0.price) } ?? "—")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(quote.map { PriceFormatter.percent($0.changePercent) } ?? "…")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 58)
                    .padding(.vertical, 1.5)
                    .glassEffect(.regular.tint(color), in: RoundedRectangle(cornerRadius: 6))
            }

            // System-standard reorder grabber: at the row's end, participates in layout (content yields automatically, no overlap with the name)
            if isReordering {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hovering ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        // In reorder mode the tap gesture must be fully detached (isEnabled), not just no-op'd in the callback —
        // the gesture recognizer itself competes with List's drag arbitration for events, making press-and-drag impossible
        .gesture(TapGesture().onEnded { onOpen() }, isEnabled: !isReordering)
        .onHover { hovering = $0 }
    }
}
