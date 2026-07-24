import SwiftUI
import PulseCore
import PulseUI

struct WatchlistShareSnapshot {
    struct Row: Identifiable {
        let id: SymbolID
        let name: String
        let market: Market
        let symbolCode: String
        let priceText: String
        let metricText: String
        let metricColorValue: Double?
        let change: Double?
        let previousClose: Double?
        let sessionLabel: String?
        let sparkline: [Candle]
    }

    let rows: [Row]
    let redUp: Bool
    let updatedAtText: String

    /// Keeps the social image mobile-friendly while avoiding a large empty field for short lists.
    /// 1...7 visible rows map to 720...1350 output pixels at the renderer's 2x scale.
    var preferredImageHeight: CGFloat {
        let visibleRows = min(max(rows.count, 1), 7)
        return min(675, max(360, 270 + CGFloat(visibleRows) * 60))
    }

    /// Mirrors the popover's content-aware metric column instead of reserving the maximum width for every list.
    var metricColumnWidth: CGFloat {
        let widths = rows.map { row in
            WatchRowColumnLayout.metricWidth(
                priceText: row.priceText,
                metricText: row.metricText,
                sessionLabel: row.sessionLabel,
                presentation: .share
            )
        }
        return widths.max() ?? 58
    }

    var titleColumnWidth: CGFloat {
        let widths = rows.map { row in
            WatchRowColumnLayout.titleWidth(
                name: row.name,
                symbolCode: row.symbolCode,
                marketName: row.market.displayName,
                presentation: .share
            )
        }
        return widths.max() ?? 58
    }

    init(rows: [Row], redUp: Bool, updatedAtText: String) {
        self.rows = rows
        self.redUp = redUp
        self.updatedAtText = updatedAtText
    }

    @MainActor
    init(appState: AppState) {
        rows = appState.watchlist.items.map { item in
            let quote = appState.market.quote(for: item.symbol)
            let metrics = quote.flatMap { PositionMetrics(item: item, quote: $0) }
            let metricDisplay = WatchRowMetricDisplay.resolve(
                quote: quote,
                metrics: metrics,
                mode: appState.settings.watchRowMetricMode,
                item: item
            )
            return Row(
                id: item.symbol,
                name: item.resolvedDisplayName,
                market: item.symbol.market,
                symbolCode: item.symbol.displayCode,
                priceText: quote.map { PriceFormatter.price($0.price) } ?? "—",
                metricText: metricDisplay.text,
                metricColorValue: metricDisplay.colorValue,
                change: quote?.change,
                previousClose: quote?.previousClose,
                sessionLabel: quote?.marketState?.extendedSessionLabel,
                sparkline: appState.market.sparklines[item.symbol] ?? []
            )
        }
        redUp = appState.settings.redUp
        // The card is rendered from live store data, so its freshness is the capture moment
        updatedAtText = PulseLocalization.localizedString(
            "refresh.updatedAt",
            Date.now.formatted(date: .omitted, time: .standard)
        )
    }
}

struct WatchlistShareContent: View {
    let snapshot: WatchlistShareSnapshot

    private let maximumVisibleRows = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(snapshot.rows.prefix(maximumVisibleRows))) { row in
                    WatchlistShareRow(
                        row: row,
                        palette: ChangePalette(redUp: snapshot.redUp),
                        titleColumnWidth: snapshot.titleColumnWidth,
                        metricColumnWidth: snapshot.metricColumnWidth
                    )

                    if row.id != snapshot.rows.prefix(maximumVisibleRows).last?.id {
                        Divider()
                            .opacity(0.45)
                    }
                }
            }

            if hiddenRowCount > 0 {
                Text(PulseLocalization.localizedString(
                    hiddenRowCount == 1
                        ? "share.watchlist.more.one"
                        : "share.watchlist.more.many",
                    hiddenRowCount
                ))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
    }

    private var hiddenRowCount: Int {
        max(snapshot.rows.count - maximumVisibleRows, 0)
    }
}

private struct WatchlistShareRow: View {
    let row: WatchlistShareSnapshot.Row
    let palette: ChangePalette
    let titleColumnWidth: CGFloat
    let metricColumnWidth: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        MarketBadge(market: row.market)
                        Text(row.symbolCode)
                            .font(.system(size: 11.5).monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: titleColumnWidth, alignment: .leading)

                IntradaySparklineView(
                    candles: row.sparkline,
                    previousClose: row.previousClose,
                    market: row.market,
                    tint: row.change.map(palette.color(for:)) ?? .secondary
                )
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let sessionLabel = row.sessionLabel {
                        Text(sessionLabel)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Text(row.priceText)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Text(row.metricText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(row.metricColorValue.map(palette.color(for:)) ?? .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
            }
            .frame(width: metricColumnWidth, alignment: .trailing)
            .layoutPriority(2)
        }
        .frame(height: 60)
    }
}
