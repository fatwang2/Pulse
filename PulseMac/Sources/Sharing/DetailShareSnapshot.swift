import SwiftUI
import PulseCore
import PulseUI

struct DetailShareSnapshot {
    struct Stat: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    let symbol: SymbolID
    let name: String
    let priceLabel: String
    let priceText: String
    let currencyCode: String?
    let changeText: String
    let changePercentText: String
    let changeValue: Double?
    let previousClose: Double?
    let period: CandlePeriod
    let periodName: String
    let trendCandles: [Candle]
    let stats: [Stat]
    let redUp: Bool
    let updatedAtText: String

    let preferredImageHeight: CGFloat = 512

    init(
        symbol: SymbolID,
        name: String,
        quote: Quote?,
        period: CandlePeriod,
        candles: [Candle],
        redUp: Bool,
        updatedAtText: String
    ) {
        self.symbol = symbol
        self.name = name
        priceLabel = quote.map(Self.priceLabel) ?? PulseLocalization.localizedString("quote.price.current")
        priceText = quote.map { PriceFormatter.price($0.price) } ?? "—"
        currencyCode = quote?.currencyCode ?? symbol.currencyCode
        changeText = quote.map { PriceFormatter.change($0.change) } ?? "—"
        changePercentText = quote.map { PriceFormatter.percent($0.changePercent) } ?? "—"
        changeValue = quote?.change
        previousClose = quote?.previousClose
        self.period = period
        periodName = period.displayName
        trendCandles = period.isIntraday
            ? IntradayTrendSnapshot(candles: candles, market: symbol.market).candles
            : candles.sorted { $0.time < $1.time }
        stats = [
            Stat(
                id: "open",
                label: PulseLocalization.localizedString("stat.open"),
                value: quote?.open.map(PriceFormatter.price) ?? "—"
            ),
            Stat(
                id: "high",
                label: PulseLocalization.localizedString("stat.high"),
                value: quote?.high.map(PriceFormatter.price) ?? "—"
            ),
            Stat(
                id: "low",
                label: PulseLocalization.localizedString("stat.low"),
                value: quote?.low.map(PriceFormatter.price) ?? "—"
            ),
            Stat(
                id: "previousClose",
                label: PulseLocalization.localizedString("stat.previousClose"),
                value: quote.map { PriceFormatter.price($0.previousClose) } ?? "—"
            ),
            Stat(
                id: "volume",
                label: PulseLocalization.localizedString("stat.volume"),
                value: quote?.volume.map(PriceFormatter.compact) ?? "—"
            ),
            Stat(
                id: "amplitude",
                label: PulseLocalization.localizedString("stat.amplitude"),
                value: quote?.amplitudePercent.map(PriceFormatter.percentMagnitude) ?? "—"
            ),
        ]
        self.redUp = redUp
        self.updatedAtText = updatedAtText
    }

    @MainActor
    init(appState: AppState, symbol: SymbolID, period: CandlePeriod, candles: [Candle]) {
        let quote = appState.market.quote(for: symbol)
        self.init(
            symbol: symbol,
            name: quote?.name ?? appState.watchlist.item(for: symbol)?.displayName ?? symbol.displayCode,
            quote: quote,
            period: period,
            candles: candles,
            redUp: appState.settings.redUp,
            updatedAtText: PulseLocalization.localizedString(
                "refresh.updatedAt",
                Date.now.formatted(date: .omitted, time: .standard)
            )
        )
    }

    private static func priceLabel(for quote: Quote) -> String {
        switch quote.marketState {
        case .preMarket:
            PulseLocalization.localizedString("quote.price.preMarket")
        case .postMarket:
            PulseLocalization.localizedString("quote.price.postMarket")
        case .overnight:
            PulseLocalization.localizedString("quote.price.overnight")
        case .closed:
            PulseLocalization.localizedString("quote.price.close")
        case .regular, .none:
            PulseLocalization.localizedString("quote.price.current")
        }
    }
}

struct DetailShareContent: View {
    let snapshot: DetailShareSnapshot

    private var palette: ChangePalette { ChangePalette(redUp: snapshot.redUp) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            identity
            quoteHero
            trend
            stats
        }
    }

    private var identity: some View {
        HStack(spacing: 8) {
            Text(snapshot.name)
                .font(.system(size: 21, weight: .bold))
                .lineLimit(1)
            MarketBadge(market: snapshot.symbol.market)
            Text(snapshot.symbol.displayCode)
                .font(.system(size: 12).monospaced())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var quoteHero: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.priceLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(snapshot.priceText)
                    .font(.system(size: 38, weight: .semibold).monospacedDigit())
                if let currencyCode = snapshot.currencyCode {
                    Text(currencyCode)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 12)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(snapshot.changeText)
                    Text(snapshot.changePercentText)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 16).monospacedDigit())
            }
            .foregroundStyle(snapshot.changeValue.map(palette.color(for:)) ?? .secondary)
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(PulseLocalization.localizedString("detail.section.trend"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(snapshot.periodName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if snapshot.trendCandles.isEmpty {
                Text(PulseLocalization.localizedString("share.updateUnavailable"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 82)
            } else if snapshot.period.isIntraday {
                IntradaySparklineView(
                    candles: snapshot.trendCandles,
                    previousClose: snapshot.previousClose,
                    market: snapshot.symbol.market,
                    tint: snapshot.changeValue.map(palette.color(for:)) ?? .secondary
                )
                .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82)
            } else {
                SparklineView(
                    values: snapshot.trendCandles.map(\.close),
                    baseline: snapshot.previousClose,
                    tint: snapshot.changeValue.map(palette.color(for:)) ?? .secondary
                )
                .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82)
            }
        }
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var stats: some View {
        Grid(horizontalSpacing: 20, verticalSpacing: 12) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(Array(snapshot.stats[(row * 3)..<(row * 3 + 3)])) { stat in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stat.label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                            Text(stat.value)
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
