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
    let title: String
    let dateText: String
    let updatedAtText: String

    /// Layout constants shared with `WatchlistShareContent`; `preferredImageHeight` must stay
    /// an upper bound of the natural content height so rows stretch instead of clipping.
    static let baseImageSize: CGFloat = 640
    static let rowMinHeight: CGFloat = 56
    private static let chromeHeight: CGFloat = 150

    /// 1:1 at the base size; width stays fixed and the card grows taller once the
    /// row stack no longer fits, so every symbol in the list is included.
    var preferredImageHeight: CGFloat {
        let rowCount = CGFloat(max(rows.count, 1))
        return max(Self.baseImageSize, Self.chromeHeight + rowCount * Self.rowMinHeight)
    }

    /// Mirrors the popover's content-aware title column instead of reserving the maximum width for every list.
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

    var priceColumnWidth: CGFloat {
        let widths = rows.map { row in
            WatchRowColumnLayout.sharePriceWidth(
                priceText: row.priceText,
                sessionLabel: row.sessionLabel
            )
        }
        return widths.max() ?? 40
    }

    var pillColumnWidth: CGFloat {
        let widths = rows.map { WatchRowColumnLayout.sharePillWidth(metricText: $0.metricText) }
        return widths.max() ?? 86
    }

    /// Tints the card ambient with the majority direction of the list; balanced lists stay neutral.
    var ambientChange: Double? {
        let ups = rows.filter { ($0.change ?? 0) > 0 }.count
        let downs = rows.filter { ($0.change ?? 0) < 0 }.count
        if ups == downs { return nil }
        return ups > downs ? 1 : -1
    }

    init(rows: [Row], redUp: Bool, title: String, dateText: String, updatedAtText: String) {
        self.rows = rows
        self.redUp = redUp
        self.title = title
        self.dateText = dateText
        self.updatedAtText = updatedAtText
    }

    @MainActor
    init(appState: AppState) {
        let rows = appState.watchlist.items.map { item in
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
                sessionLabel: appState.isIndex(item.symbol)
                    ? nil
                    : quote?.marketState?.extendedSessionLabel,
                sparkline: appState.market.sparklines[item.symbol] ?? []
            )
        }
        let locale = appState.settings.locale
        // The shared list is the selected tag, so the card is titled after it
        let groupName = appState.watchlist.selectedGroup?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // The card is rendered from live store data, so its freshness is the capture moment
        self.init(
            rows: rows,
            redUp: appState.settings.redUp,
            title: groupName.isEmpty
                ? PulseLocalization.localizedString("share.watchlist.title")
                : groupName,
            dateText: Date.now.formatted(
                Date.FormatStyle(locale: locale)
                    .month().day().weekday(.abbreviated)
            ),
            updatedAtText: PulseLocalization.localizedString(
                "refresh.updatedAt",
                Date.now.formatted(
                    Date.FormatStyle(locale: locale).hour().minute()
                )
            )
        )
    }
}

struct WatchlistShareContent: View {
    let snapshot: WatchlistShareSnapshot

    var body: some View {
        VStack(spacing: 0) {
            header
            rows
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(snapshot.title)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
            Text(snapshot.dateText)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 12)
            Text(snapshot.updatedAtText)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                        .opacity(0.45)
                }
                WatchlistShareRow(
                    row: row,
                    palette: ChangePalette(redUp: snapshot.redUp),
                    titleColumnWidth: snapshot.titleColumnWidth,
                    priceColumnWidth: snapshot.priceColumnWidth,
                    pillColumnWidth: snapshot.pillColumnWidth
                )
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct WatchlistShareRow: View {
    let row: WatchlistShareSnapshot.Row
    let palette: ChangePalette
    let titleColumnWidth: CGFloat
    let priceColumnWidth: CGFloat
    let pillColumnWidth: CGFloat

    private var metricColor: Color? {
        row.metricColorValue.map(palette.color(for:))
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.system(size: 14.5, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    MarketBadge(market: row.market)
                    Text(row.symbolCode)
                        .font(.system(size: 11.5).monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: titleColumnWidth, alignment: .leading)

            // Mirrors the list rows: share sparklines frame the regular
            // session only.
            IntradaySparklineView(
                candles: row.sparkline,
                previousClose: row.previousClose,
                market: row.market,
                tint: row.change.map(palette.color(for:)) ?? .secondary,
                includesExtendedHours: false
            )
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)

            VStack(alignment: .trailing, spacing: 2.5) {
                if let sessionLabel = row.sessionLabel {
                    Text(sessionLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Text(row.priceText)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: priceColumnWidth, alignment: .trailing)

            Text(row.metricText)
                .font(.system(size: 13.5, weight: .bold).monospacedDigit())
                .foregroundStyle(metricColor ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
                .frame(width: pillColumnWidth, height: 27)
                .background(
                    (metricColor ?? .secondary).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .frame(minHeight: WatchlistShareSnapshot.rowMinHeight, maxHeight: .infinity)
    }
}
