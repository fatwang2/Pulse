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
    let dayLowText: String?
    let dayHighText: String?
    let amplitudeText: String?
    /// Current price's position within the day range, 0 (low) ... 1 (high).
    let dayRangeFraction: Double?
    let redUp: Bool
    let stampText: String
    let updatedAtText: String

    /// 16:9 landscape, X's native in-stream ratio.
    static let imageSize = CGSize(width: 960, height: 540)

    init(
        symbol: SymbolID,
        name: String,
        quote: Quote?,
        period: CandlePeriod,
        candles: [Candle],
        redUp: Bool,
        updatedAtText: String,
        capturedAt: Date = .now
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
                id: "previousClose",
                label: PulseLocalization.localizedString("stat.previousClose"),
                value: quote.map { PriceFormatter.price($0.previousClose) } ?? "—"
            ),
            Stat(
                id: "volume",
                label: PulseLocalization.localizedString("stat.volume"),
                value: quote?.volume.map(PriceFormatter.compact) ?? "—"
            ),
        ]
        dayLowText = quote?.low.map(PriceFormatter.price)
        dayHighText = quote?.high.map(PriceFormatter.price)
        amplitudeText = quote?.amplitudePercent.map(PriceFormatter.percentMagnitude)
        if let quote, let low = quote.low, let high = quote.high, high > low {
            dayRangeFraction = min(max((quote.price - low) / (high - low), 0), 1)
        } else {
            dayRangeFraction = nil
        }
        self.redUp = redUp
        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyy.MM.dd HH:mm"
        stampText = stampFormatter.string(from: capturedAt)
        self.updatedAtText = updatedAtText
    }

    @MainActor
    init(appState: AppState, symbol: SymbolID, period: CandlePeriod, candles: [Candle]) {
        let quote = appState.market.quote(for: symbol)
        self.init(
            symbol: symbol,
            name: appState.displayName(for: symbol),
            quote: quote,
            period: period,
            candles: candles,
            redUp: appState.settings.redUp,
            updatedAtText: PulseLocalization.localizedString(
                "refresh.updatedAt",
                Date.now.formatted(date: .omitted, time: .shortened)
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
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: DetailShareSnapshot

    private var palette: ChangePalette { ChangePalette(redUp: snapshot.redUp) }

    private var changeColor: Color {
        snapshot.changeValue.map(palette.color(for:)) ?? .secondary
    }

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(width: 330)
            chartPanel
        }
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(snapshot.name)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                MarketBadge(market: snapshot.symbol.market)
                Text(snapshot.symbol.displayCode)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(snapshot.stampText)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 7)

            Text(snapshot.priceLabel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 26)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snapshot.priceText)
                    .font(.system(size: 46, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let currencyCode = snapshot.currencyCode {
                    Text(currencyCode)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 6)

            changePill
                .padding(.top, 13)

            if snapshot.dayLowText != nil {
                dayRange
                    .padding(.top, 24)
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(snapshot.stats) { stat in
                    HStack {
                        Text(stat.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(stat.value)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.system(size: 12.5))
                }
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 26)
        .padding(.top, 26)
        .padding(.bottom, 18)
    }

    private var changePill: some View {
        HStack(spacing: 7) {
            if let change = snapshot.changeValue, change != 0 {
                Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 10, weight: .bold))
            }
            Text(snapshot.changePercentText)
                .font(.system(size: 16, weight: .bold).monospacedDigit())
            Text(snapshot.changeText)
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .opacity(0.85)
        }
        .foregroundStyle(changeColor)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(changeColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var dayRange: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(PulseLocalization.localizedString("share.range.intraday"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                if let amplitudeText = snapshot.amplitudeText {
                    Text(amplitudeText)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.color(isUp: false).opacity(0.25),
                                    palette.color(isUp: true).opacity(0.25),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 5)

                    if let fraction = snapshot.dayRangeFraction {
                        Circle()
                            .fill(changeColor)
                            .frame(width: 11, height: 11)
                            .overlay(
                                Circle().strokeBorder(
                                    colorScheme == .dark
                                        ? Color(red: 0.063, green: 0.071, blue: 0.094)
                                        : Color(red: 0.973, green: 0.976, blue: 0.985),
                                    lineWidth: 2.5
                                )
                            )
                            .offset(x: (proxy.size.width - 11) * fraction)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 13)
            .padding(.top, 9)

            HStack {
                Text(snapshot.dayLowText ?? "—")
                Spacer()
                Text(snapshot.dayHighText ?? "—")
            }
            .font(.system(size: 10.5).monospacedDigit())
            .foregroundStyle(.tertiary)
            .padding(.top, 7)
        }
    }

    // MARK: - Chart panel

    /// Chart bleeds to the card's left-panel boundary and bottom, with breathing room on the right.
    private var chartPanel: some View {
        ZStack(alignment: .topTrailing) {
            if snapshot.trendCandles.isEmpty {
                Text(PulseLocalization.localizedString("share.updateUnavailable"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    chart
                        .padding(.top, 34)
                        .padding(.bottom, 26)
                        .padding(.trailing, 28)
                        .overlay(alignment: .topLeading) {
                            baselineTag(in: proxy.size)
                        }
                }
            }

            Text(snapshot.periodName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
                .padding(.trailing, 28)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if snapshot.period.isIntraday {
            IntradaySparklineView(
                candles: snapshot.trendCandles,
                previousClose: snapshot.previousClose,
                market: snapshot.symbol.market,
                tint: changeColor
            )
        } else {
            SparklineView(
                values: snapshot.trendCandles.map(\.close),
                baseline: snapshot.previousClose,
                tint: changeColor
            )
        }
    }

    @ViewBuilder
    private func baselineTag(in size: CGSize) -> some View {
        if let previousClose = snapshot.previousClose,
           let fraction = baselineFraction(previousClose: previousClose) {
            let plotHeight = size.height - 34 - 26
            Text(PulseLocalization.localizedString("stat.previousClose") + " " + PriceFormatter.price(previousClose))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: size.width - 28 - 8, alignment: .trailing)
                .offset(y: 34 + plotHeight * fraction - 16)
        }
    }

    /// Mirrors the y-domain math of the chart views so the previous-close caption
    /// lands on the dashed rule they draw (10% padding intraday, 8% otherwise).
    private func baselineFraction(previousClose: Double) -> CGFloat? {
        let closes = snapshot.trendCandles.map(\.close)
        guard closes.count > 1 else { return nil }
        var lo = min(closes.min() ?? previousClose, previousClose)
        var hi = max(closes.max() ?? previousClose, previousClose)
        let pad = snapshot.period.isIntraday
            ? max((hi - lo) * 0.1, hi * 0.001, 0.0001)
            : max((hi - lo) * 0.08, hi * 0.0005, 0.0001)
        lo -= pad
        hi += pad
        guard hi > lo else { return nil }
        return CGFloat(1 - (previousClose - lo) / (hi - lo))
    }
}
