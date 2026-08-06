import Foundation
import PulseCore

/// Fixed-English, model-friendly text exports for the current Pulse surface.
/// The payload carries market facts only: no analysis instructions, positions, or trade history.
struct WatchlistTextSnapshot {
    struct Item {
        let symbol: SymbolID
        let name: String
        let instrumentType: InstrumentType?
        let quote: Quote?
        let intradayCandles: [Candle]
    }

    let groupName: String
    let items: [Item]
    let exportedAt: Date

    @MainActor
    init(appState: AppState, exportedAt: Date = .now) {
        self.init(
            watchlist: appState.watchlist,
            market: appState.market,
            prioritizeOpenMarkets: appState.settings.prioritizeOpenMarkets,
            exportedAt: exportedAt
        )
    }

    @MainActor
    init(
        watchlist: WatchlistStore,
        market: MarketStore,
        prioritizeOpenMarkets: Bool = true,
        exportedAt: Date = .now
    ) {
        groupName = watchlist.selectedGroup?.name ?? ""
        let displayItems = WatchlistDisplayOrder.items(
            from: watchlist,
            prioritizeOpenMarkets: prioritizeOpenMarkets,
            at: exportedAt
        )
        items = displayItems.map { item in
            Item(
                symbol: item.symbol,
                name: item.resolvedDisplayName,
                instrumentType: item.resolvedInstrumentType,
                quote: market.quote(for: item.symbol),
                intradayCandles: IntradayTrendSnapshot(
                    candles: market.sparklines[item.symbol] ?? [],
                    market: item.symbol.market,
                    includesExtendedHours: false
                ).candles
            )
        }
        self.exportedAt = exportedAt
    }

    init(groupName: String, items: [Item], exportedAt: Date) {
        self.groupName = groupName
        self.items = items
        self.exportedAt = exportedAt
    }

    func renderedText() throws -> String {
        try MarketTextRenderer.render([
            "exported_at": MarketTextRenderer.utcTimestamp(exportedAt),
            "exported_by": "Pulse",
            "format": "pulse_market_snapshot",
            "items": items.enumerated().map { offset, item in
                [
                    "instrument": MarketTextRenderer.instrument(
                        symbol: item.symbol,
                        name: item.name,
                        instrumentType: item.instrumentType,
                        currencyCode: item.quote?.currencyCode
                    ),
                    "intraday_summary": MarketTextRenderer.intradaySummary(
                        candles: item.intradayCandles,
                        symbol: item.symbol
                    ),
                    "order": offset + 1,
                    "quote": MarketTextRenderer.quote(item.quote),
                ] as [String: Any]
            },
            "product_url": MarketTextRenderer.productURL,
            "schema_version": 1,
            "view": [
                "group_name": groupName,
                "type": "watchlist",
            ],
        ])
    }
}

struct DetailTextSnapshot {
    let symbol: SymbolID
    let name: String
    let instrumentType: InstrumentType?
    let quote: Quote
    let period: CandlePeriod
    let candles: [Candle]
    let includesExtendedHours: Bool
    let exportedAt: Date

    init(
        symbol: SymbolID,
        name: String,
        instrumentType: InstrumentType?,
        quote: Quote,
        period: CandlePeriod,
        candles: [Candle],
        includesExtendedHours: Bool,
        exportedAt: Date = .now
    ) {
        self.symbol = symbol
        self.name = name
        self.instrumentType = instrumentType
        self.quote = quote
        self.period = period
        self.candles = candles
        self.includesExtendedHours = includesExtendedHours && period.isIntraday
        self.exportedAt = exportedAt
    }

    func renderedText() throws -> String {
        try MarketTextRenderer.render([
            "chart": MarketTextRenderer.chart(
                candles: candles,
                period: period,
                symbol: symbol,
                includesExtendedHours: includesExtendedHours
            ),
            "exported_at": MarketTextRenderer.utcTimestamp(exportedAt),
            "exported_by": "Pulse",
            "format": "pulse_market_snapshot",
            "instrument": MarketTextRenderer.instrument(
                symbol: symbol,
                name: name,
                instrumentType: instrumentType,
                currencyCode: quote.currencyCode
            ),
            "product_url": MarketTextRenderer.productURL,
            "quote": MarketTextRenderer.quote(quote),
            "schema_version": 1,
            "view": ["type": "detail"],
        ], compactChartBars: true)
    }
}

private enum MarketTextRenderer {
    static let maximumChartBars = 120
    static let productURL = "https://www.pulseticker.app"
    static let preamble = "This market snapshot was exported by Pulse. Market data may be real-time or delayed; refer to each record's source, timestamp, and session fields."

    static func render(
        _ object: [String: Any],
        compactChartBars: Bool = false
    ) throws -> String {
        var encodedObject = object
        var compactRows: [[Any]]?
        let barsMarker = "__pulse_compact_chart_bars_\(UUID().uuidString)__"
        if compactChartBars {
            guard var chart = encodedObject["chart"] as? [String: Any],
                  let rows = chart["bars"] as? [[Any]] else {
                throw MarketTextSnapshotError.encodingFailed
            }
            compactRows = rows
            chart["bars"] = barsMarker
            encodedObject["chart"] = chart
        }

        guard JSONSerialization.isValidJSONObject(encodedObject) else {
            throw MarketTextSnapshotError.encodingFailed
        }
        let data = try JSONSerialization.data(
            withJSONObject: encodedObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard var json = String(data: data, encoding: .utf8) else {
            throw MarketTextSnapshotError.encodingFailed
        }

        if let compactRows {
            let rowStrings = try compactRows.map { row -> String in
                let rowData = try JSONSerialization.data(
                    withJSONObject: row,
                    options: [.withoutEscapingSlashes]
                )
                guard let rowString = String(data: rowData, encoding: .utf8) else {
                    throw MarketTextSnapshotError.encodingFailed
                }
                return rowString
            }
            let rowsJSON = rowStrings.isEmpty
                ? "[]"
                : "[\n      \(rowStrings.joined(separator: ",\n      "))\n    ]"
            let markerJSON = "\"\(barsMarker)\""
            guard let markerRange = json.range(of: markerJSON) else {
                throw MarketTextSnapshotError.encodingFailed
            }
            json.replaceSubrange(markerRange, with: rowsJSON)
        }

        return "\(preamble)\n\n```json\n\(json)\n```"
    }

    static func instrument(
        symbol: SymbolID,
        name: String,
        instrumentType: InstrumentType?,
        currencyCode: String?
    ) -> [String: Any] {
        [
            "currency_code": currencyCode ?? symbol.currencyCode,
            "instrument_type": instrumentType?.rawValue ?? NSNull(),
            "market": symbol.market.rawValue,
            "market_timezone": symbol.market.timeZone.identifier,
            "name": name,
            "symbol": symbol.displayCode,
            "volume_unit": symbol.cryptoPair?.baseAsset ?? "shares",
        ]
    }

    static func quote(_ quote: Quote?) -> Any {
        guard let quote else { return NSNull() }
        let hasReferenceClose = quote.previousClose.isFinite && quote.previousClose != 0
        let hasPrice = quote.price.isFinite
        let regularSession: Any
        let priceDigits = priceFractionDigits(for: quote.symbol)
        if let regular = quote.regularSession {
            let validReference = regular.previousClose?.isFinite == true && regular.previousClose != 0
            regularSession = [
                "change": validReference
                    ? decimalNumber(regular.change, fractionDigits: priceDigits)
                    : NSNull(),
                "change_percent": validReference ? percentNumber(regular.changePercent) : NSNull(),
                "previous_close": validReference
                    ? decimalNumber(regular.previousClose, fractionDigits: priceDigits)
                    : NSNull(),
                "price": decimalNumber(regular.price, fractionDigits: priceDigits),
            ] as [String: Any]
        } else {
            regularSession = NSNull()
        }

        return [
            "change": hasPrice && hasReferenceClose
                ? decimalNumber(quote.price - quote.previousClose, fractionDigits: priceDigits)
                : NSNull(),
            "change_percent": hasPrice && hasReferenceClose
                ? percentNumber((quote.price - quote.previousClose) / quote.previousClose * 100)
                : NSNull(),
            "high": decimalNumber(quote.high, fractionDigits: priceDigits),
            "low": decimalNumber(quote.low, fractionDigits: priceDigits),
            "open": decimalNumber(quote.open, fractionDigits: priceDigits),
            "previous_close": hasReferenceClose
                ? decimalNumber(quote.previousClose, fractionDigits: priceDigits)
                : NSNull(),
            "price": decimalNumber(quote.price, fractionDigits: priceDigits),
            "regular_session_close": regularSession,
            "session": session(quote.marketState, market: quote.symbol.market),
            "source": [
                "delay_seconds": decimalNumber(quote.sourceDelay, fractionDigits: 0),
                "id": quote.sourceID ?? NSNull(),
                "name": quote.sourceName ?? NSNull(),
            ],
            "timestamp": marketTimestamp(quote.timestamp, market: quote.symbol.market),
            "turnover": decimalNumber(quote.turnover, fractionDigits: 2),
            "volume": volumeNumber(quote.volume, symbol: quote.symbol),
        ] as [String: Any]
    }

    static func intradaySummary(candles: [Candle], symbol: SymbolID) -> Any {
        let market = symbol.market
        let sorted = exactCurrentSessionCandles(
            candles,
            market: market,
            includesExtendedHours: false
        )
        guard let first = sorted.first, let last = sorted.last else { return NSNull() }
        let priceDigits = priceFractionDigits(for: symbol)
        return [
            "bar_count": sorted.count,
            "close": decimalNumber(last.close, fractionDigits: priceDigits),
            "end_at": marketTimestamp(last.time, market: market),
            "high": decimalNumber(
                sorted.map(\.high).filter(\.isFinite).max(),
                fractionDigits: priceDigits
            ),
            "low": decimalNumber(
                sorted.map(\.low).filter(\.isFinite).min(),
                fractionDigits: priceDigits
            ),
            "open": decimalNumber(first.open, fractionDigits: priceDigits),
            "period": "1m",
            "session_scope": market == .crypto ? "continuous" : "regular",
            "source": NSNull(),
            "start_at": marketTimestamp(first.time, market: market),
            "volume": volumeNumber(summedVolumeValue(sorted), symbol: symbol),
        ] as [String: Any]
    }

    static func chart(
        candles: [Candle],
        period: CandlePeriod,
        symbol: SymbolID,
        includesExtendedHours: Bool
    ) -> [String: Any] {
        let market = symbol.market
        let sorted = candles.sorted { $0.time < $1.time }
        let input = period == .minute1
            ? exactCurrentSessionCandles(
                sorted,
                market: market,
                includesExtendedHours: includesExtendedHours
            )
            : sorted
        let factor = max(Int(ceil(Double(input.count) / Double(maximumChartBars))), 1)
        let output = factor == 1 ? input : stride(from: 0, to: input.count, by: factor).compactMap { start in
            aggregate(Array(input[start..<min(start + factor, input.count)]))
        }
        let priceDigits = priceFractionDigits(for: symbol)
        return [
            "aggregation": [
                "input_bar_count": input.count,
                "method": factor == 1 ? "none" : "contiguous_ohlcv",
                "output_bar_count": output.count,
                "source_bars_per_output_bar": factor,
            ],
            "bar_columns": ["time", "open", "high", "low", "close", "volume"],
            "bars": output.map { candle in
                [
                    marketTimestamp(candle.time, market: market),
                    decimalNumber(candle.open, fractionDigits: priceDigits),
                    decimalNumber(candle.high, fractionDigits: priceDigits),
                    decimalNumber(candle.low, fractionDigits: priceDigits),
                    decimalNumber(candle.close, fractionDigits: priceDigits),
                    volumeNumber(candle.volume, symbol: symbol),
                ] as [Any]
            },
            "includes_extended_hours": includesExtendedHours,
            "period": periodCode(period),
            "session_scope": sessionScope(
                period: period,
                market: market,
                includesExtendedHours: includesExtendedHours
            ),
            "source": NSNull(),
            "visible_from": optionalTimestamp(input.first?.time, market: market),
            "visible_to": optionalTimestamp(input.last?.time, market: market),
        ]
    }

    static func utcTimestamp(_ date: Date) -> String {
        timestamp(date, timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    private static func marketTimestamp(_ date: Date, market: Market) -> String {
        timestamp(date, timeZone: market.timeZone)
    }

    private static func optionalTimestamp(_ date: Date?, market: Market) -> Any {
        guard let date else { return NSNull() }
        return marketTimestamp(date, market: market)
    }

    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return formatter.string(from: date)
    }

    private static func aggregate(_ candles: [Candle]) -> Candle? {
        guard let first = candles.first, let last = candles.last else { return nil }
        return Candle(
            time: first.time,
            open: first.open,
            high: candles.map(\.high).filter(\.isFinite).max() ?? first.high,
            low: candles.map(\.low).filter(\.isFinite).min() ?? first.low,
            close: last.close,
            volume: summedVolumeValue(candles)
        )
    }

    private static func summedVolumeValue(_ candles: [Candle]) -> Double? {
        let values = candles.compactMap(\.volume)
        guard values.count == candles.count, values.allSatisfy(\.isFinite) else { return nil }
        return values.reduce(0, +)
    }

    private static func decimalNumber(_ value: Double?, fractionDigits: Int) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        var decimal = Decimal(value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, fractionDigits, .plain)
        return rounded
    }

    private static func priceFractionDigits(for symbol: SymbolID) -> Int {
        symbol.market == .crypto ? 8 : 2
    }

    private static func percentNumber(_ value: Double?) -> Any {
        decimalNumber(value, fractionDigits: 4)
    }

    private static func volumeNumber(_ value: Double?, symbol: SymbolID) -> Any {
        decimalNumber(value, fractionDigits: symbol.market == .crypto ? 8 : 0)
    }

    private static func session(_ state: MarketState?, market: Market) -> Any {
        if market == .crypto { return "continuous" }
        guard let state else { return NSNull() }
        return switch state {
        case .preMarket: "pre_market"
        case .regular: "regular"
        case .postMarket: "post_market"
        case .overnight: "overnight"
        case .closed: "closed"
        }
    }

    /// Chart session framing deliberately accepts provider bars one minute outside the
    /// exchange boundary. Text exports claim an exact scope, so trim that tolerance here
    /// without changing the shared chart behavior.
    private static func exactCurrentSessionCandles(
        _ candles: [Candle],
        market: Market,
        includesExtendedHours: Bool
    ) -> [Candle] {
        let sorted = candles.sorted { $0.time < $1.time }
        guard let referenceDate = sorted.last?.time else { return [] }
        let session = IntradayTradingSession(
            market: market,
            referenceDate: referenceDate,
            includesExtendedHours: includesExtendedHours
        )
        let start = session.preOpen ?? session.open
        let end = session.postClose ?? session.close
        return sorted.filter { $0.time >= start && $0.time <= end }
    }

    private static func periodCode(_ period: CandlePeriod) -> String {
        switch period {
        case .minute1: "1m"
        case .minute5: "5m"
        case .minute15: "15m"
        case .minute30: "30m"
        case .hour1: "1h"
        case .day: "1d"
        case .week: "1w"
        case .month: "1mo"
        }
    }

    private static func sessionScope(
        period: CandlePeriod,
        market: Market,
        includesExtendedHours: Bool
    ) -> Any {
        guard period.isIntraday else { return NSNull() }
        if market == .crypto { return "continuous" }
        if market == .us && includesExtendedHours { return "pre_market_regular_post_market" }
        return "regular"
    }
}

enum MarketTextSnapshotError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "The market snapshot could not be encoded as text."
    }
}
