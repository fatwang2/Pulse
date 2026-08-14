import SwiftUI
import PulseCore
import PulseUI

/// One watchlist line: identity on the left, the session's shape in the middle,
/// price plus a solid change chip on the right — the Mac popover row, re-spaced
/// for a phone list.
struct QuoteRow: View {
    @Environment(IOSAppState.self) private var appState

    let item: WatchItem

    private let titleColumnWidth: CGFloat = 86
    private let metricColumnWidth: CGFloat = 76

    private var quote: Quote? { appState.market.quote(for: item.symbol) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.displayName(for: item.symbol))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 5) {
                    MarketBadge(market: item.symbol.market)
                    Text(item.symbol.displayCode)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: titleColumnWidth, alignment: .leading)

            sparkline

            VStack(alignment: .trailing, spacing: 3) {
                Text(quote.map { PriceFormatter.price($0.price) } ?? "—")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
                changeChip
            }
            .frame(width: metricColumnWidth, alignment: .trailing)
            .clipped()
            .layoutPriority(2)
        }
        .padding(.vertical, 2)
        .animation(.default, value: quote?.price)
    }

    private var sparkline: some View {
        let candles = appState.market.sparklines[item.symbol] ?? []
        let change = quote?.change ?? 0
        return IntradaySparklineView(
            candles: candles,
            previousClose: quote?.previousClose,
            market: item.symbol.market,
            tint: appState.palette.color(for: change),
            // Match the Mac list: at row size, extended-hours wings add noise.
            // The detail page remains the only place where the setting applies.
            includesExtendedHours: false
        )
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .layoutPriority(1)
        .opacity(candles.isEmpty ? 0 : 1)
    }

    private var changeChip: some View {
        let percent = quote?.changePercent
        let color = percent.map { appState.palette.color(for: $0) } ?? Color.secondary
        return Text(percent.map { PriceFormatter.percent($0) } ?? "—")
            .font(.caption.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(percent == nil ? 0.35 : 1), in: Capsule())
            .contentTransition(.numericText())
    }
}
