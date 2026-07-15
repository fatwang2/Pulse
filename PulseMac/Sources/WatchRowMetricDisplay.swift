import PulseCore
import PulseUI

/// Pure display calculation shared by the live watch row and off-screen share snapshots.
struct WatchRowMetricDisplay {
    let text: String
    let colorValue: Double?

    static func resolve(
        quote: Quote?,
        metrics: PositionMetrics?,
        mode: WatchRowMetricMode,
        item: WatchItem
    ) -> Self {
        guard let quote else {
            return Self(text: "…", colorValue: nil)
        }

        let currencyCode = quote.currencyCode ?? item.symbol.currencyCode
        switch mode {
        case .changePercent:
            return Self(
                text: PriceFormatter.percent(quote.changePercent),
                colorValue: quote.change
            )
        case .todayPnL:
            guard let metrics else {
                return fallbackPercent(quote)
            }
            return Self(
                text: PriceFormatter.signedMoney(metrics.todayPnL, currencyCode: currencyCode),
                colorValue: metrics.todayPnL
            )
        case .totalPnL, .summary:
            guard let metrics else {
                return fallbackPercent(quote)
            }
            return Self(
                text: PriceFormatter.signedMoney(metrics.totalPnL, currencyCode: currencyCode),
                colorValue: metrics.totalPnL
            )
        }
    }

    private static func fallbackPercent(_ quote: Quote) -> Self {
        Self(
            text: PriceFormatter.percent(quote.changePercent),
            colorValue: quote.change
        )
    }
}
