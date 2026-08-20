import Foundation

/// Naver Finance (naver.com, unofficial API) — Korea, in real time.
///
/// Yahoo reaches both Korean boards but ~20 minutes late and indexed in English
/// only: `삼성전자` finds nothing there. Naver publishes the same instruments
/// with `delayTime: 0`, its own autocomplete answers Korean, and its charts run
/// from one-minute bars to monthly. It is therefore the source for Korea, with
/// Yahoo left as the failover and as the way an English name is still found.
///
/// One address quirk shapes the whole file: Naver identifies a stock by its bare
/// code, never by board. That is what makes it authoritative about which board a
/// code belongs to — the answer carries `KS` or `KQ` — and it is also why a quote
/// still resolves when Pulse has the board recorded wrong, where Yahoo's
/// suffixed symbol would silently price something else.
public struct NaverProvider: QuoteProvider {
    public static let providerID = "naver"

    /// Naver refuses requests without a finance referer.
    private static let headers = [
        "Referer": "https://finance.naver.com/",
        "User-Agent": "Mozilla/5.0",
    ]

    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: Self.providerID,
            name: PulseLocalization.localizedString("provider.naver"),
            markets: [.kr, .kq],
            capabilities: [.search, .quotes, .candles],
            candleMarkets: [.kr, .kq],
            candlePeriods: [.minute1, .minute5, .minute15, .minute30, .hour1, .day, .week, .month],
            delay: [.kr: 0, .kq: 0],
            // Naver's own page polls every seven seconds; Pulse settles for the
            // cadence it gives the other unofficial sources.
            rateLimit: RateLimitPolicy(minInterval: 1, batchSize: 20),
            suggestedPollInterval: 15
        )
    }

    // MARK: - Symbol mapping

    /// Naver's path segment for an instrument: an index has a name, everything
    /// else its plain exchange code.
    static func naverCode(for symbol: SymbolID) -> String? {
        if let index = symbol.indexID {
            return switch index {
            case .kospi: "KOSPI"
            default: nil
            }
        }
        guard symbol.market.isKorea else { return nil }
        let code = symbol.code.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }

    /// Indices live under a different path than stocks on every Naver endpoint.
    static func isIndex(_ symbol: SymbolID) -> Bool { symbol.indexID != nil }

    /// The board a Naver result belongs to. `KS` is KOSPI, `KQ` KOSDAQ; anything
    /// else (KONEX, foreign listings) is not modeled and is dropped rather than
    /// guessed at.
    static func market(forExchangeCode code: String) -> Market? {
        switch code.uppercased() {
        case "KS", "KOSPI": .kr
        case "KQ", "KOSDAQ": .kq
        default: nil
        }
    }

    // MARK: - QuoteProvider

    public func search(_ query: String) async throws -> [SymbolInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://ac.stock.naver.com/ac")!
        components.queryItems = [
            .init(name: "q", value: trimmed),
            .init(name: "target", value: "stock,index"),
        ]
        let data = try await http.get(components.url!, headers: Self.headers)
        return try Self.parseSearch(data)
    }

    static func parseSearch(_ data: Data) throws -> [SymbolInfo] {
        struct Response: Decodable {
            struct Item: Decodable {
                let code: String
                let name: String
                let typeCode: String?
                let typeName: String?
                let category: String?
                let nationCode: String?
            }
            let items: [Item]?
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProviderError.badResponse("naver search: \(error.localizedDescription)")
        }

        return (response.items ?? []).compactMap { item -> SymbolInfo? in
            switch item.category {
            case "stock":
                // The same endpoint answers with Hong Kong and US listings for a
                // Latin query ("samsung" returns Samsung's HK ETFs), and this
                // provider speaks for Korea only.
                guard item.nationCode == "KOR",
                      let market = item.typeCode.flatMap(Self.market(forExchangeCode:))
                else { return nil }
                return SymbolInfo(
                    symbol: SymbolID(market: market, code: item.code),
                    name: item.name,
                    exchangeName: item.typeName,
                    // Korean ETFs come back as ordinary listings with no marker
                    // of their own, so everything tradable is an equity here.
                    type: .equity
                )
            case "index":
                // Naver lists a dozen Korean indices and their futures; Pulse
                // models the composite alone, so the rest are dropped.
                guard item.code.uppercased() == "KOSPI" else { return nil }
                return SymbolInfo(
                    symbol: SymbolID(index: .kospi),
                    name: item.name,
                    exchangeName: item.typeName,
                    type: .index
                )
            default:
                return nil
            }
        }
    }

    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }

        // Indices and stocks are separate paths, so they cannot share a batch.
        let indices = symbols.filter(Self.isIndex)
        let stocks = symbols.filter { !Self.isIndex($0) }

        var quotes: [Quote] = []
        if !stocks.isEmpty {
            quotes += try await batchQuotes(for: stocks, path: "stock")
        }
        for index in indices {
            quotes += try await batchQuotes(for: [index], path: "index")
        }
        guard !quotes.isEmpty else {
            throw ProviderError.symbolNotFound(symbols[0])
        }
        return quotes
    }

    private func batchQuotes(for symbols: [SymbolID], path: String) async throws -> [Quote] {
        let requested = symbols.reduce(into: [String: SymbolID]()) { map, symbol in
            if let code = Self.naverCode(for: symbol) { map[code.uppercased()] = symbol }
        }
        guard !requested.isEmpty else { throw ProviderError.unsupported(.quotes) }

        let list = requested.keys.sorted().joined(separator: ",")
        let encoded = list.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? list
        let url = URL(string: "https://polling.finance.naver.com/api/realtime/domestic/\(path)/\(encoded)")!
        let data = try await http.get(url, headers: Self.headers)
        return try Self.parseQuotes(data, requested: requested)
    }

    /// A code Naver does not know is not an error: the endpoint answers 200 with
    /// an empty `datas` array, and the symbol simply goes unquoted.
    static func parseQuotes(_ data: Data, requested: [String: SymbolID]) throws -> [Quote] {
        let response: NaverQuoteResponse
        do {
            response = try JSONDecoder().decode(NaverQuoteResponse.self, from: data)
        } catch {
            throw ProviderError.badResponse("naver quotes: \(error.localizedDescription)")
        }

        return (response.datas ?? []).compactMap { row -> Quote? in
            guard let symbol = requested[row.itemCode.uppercased()],
                  let price = row.close, price > 0
            else { return nil }
            // Naver reports the move, not the reference, and signs it: a decline
            // arrives as a negative number rather than a direction flag.
            let previousClose = price - (row.change ?? 0)

            return Quote(
                symbol: symbol,
                name: row.stockName?.trimmingCharacters(in: .whitespacesAndNewlines),
                price: price,
                previousClose: previousClose > 0 ? previousClose : price,
                open: row.open,
                high: row.high,
                low: row.low,
                volume: row.volume,
                turnover: row.turnover,
                currencyCode: symbol.currencyCode,
                timestamp: row.localTradedAt.flatMap(Self.timestamp(from:)) ?? .now
            )
        }
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard let code = Self.naverCode(for: symbol) else {
            throw ProviderError.unsupported(.candles)
        }
        let path = Self.isIndex(symbol) ? "index" : "item"
        // Naver serves one-minute bars and daily/weekly/monthly ones natively;
        // the resolutions in between are folded out of the minute line.
        let base: CandlePeriod = period.isIntraday ? .minute1 : period
        let bars = try await Self.fetchCandles(
            http: http, path: path, code: code, endpoint: Self.endpoint(for: base),
            days: Self.lookbackDays(for: period, count: count), intraday: base.isIntraday
        )
        let candles = CandleResampler.resample(bars, into: period, timeZone: Market.kr.timeZone)
        guard !candles.isEmpty else {
            throw ProviderError.badResponse("naver: no candles parsed for \(code)")
        }
        return Array(candles.suffix(count))
    }

    static func endpoint(for period: CandlePeriod) -> String {
        switch period {
        case .minute1, .minute5, .minute15, .minute30, .hour1: "minute"
        case .day: "day"
        case .week: "week"
        case .month: "month"
        }
    }

    /// Both chart endpoints take a window rather than a bar count, so the count
    /// is turned into calendar days with enough slack for weekends and holidays.
    static func lookbackDays(for period: CandlePeriod, count: Int) -> Int {
        let count = max(count, 1)
        switch period {
        case .minute1, .minute5, .minute15, .minute30, .hour1:
            // A Seoul session is 390 one-minute bars.
            let baseBars = count * (period.intradayMinutes ?? 1)
            return min(max(baseBars / 390 + 3, 4), 40)
        case .day: return min(count * 2 + 10, 4_000)
        case .week: return min(count * 9, 8_000)
        case .month: return min(count * 32, 20_000)
        }
    }

    private static func fetchCandles(
        http: HTTPClient, path: String, code: String, endpoint: String, days: Int, intraday: Bool
    ) async throws -> [Candle] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Market.kr.timeZone
        formatter.dateFormat = "yyyyMMddHHmm"

        let end = Date.now
        let start = end.addingTimeInterval(-Double(days) * 86_400)
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        var components = URLComponents(
            string: "https://api.stock.naver.com/chart/domestic/\(path)/\(encoded)/\(endpoint)"
        )!
        components.queryItems = [
            .init(name: "startDateTime", value: formatter.string(from: start)),
            .init(name: "endDateTime", value: formatter.string(from: end)),
        ]
        let data = try await http.get(components.url!, headers: headers)
        return try parseCandles(data, intraday: intraday)
    }

    /// `[{"localDate":"20260102", …}]` for daily and coarser bars,
    /// `[{"localDateTime":"20260820090000", …}]` for the minute line, where the
    /// bar's close is spelled `currentPrice`.
    static func parseCandles(_ data: Data, intraday: Bool) throws -> [Candle] {
        struct Row: Decodable {
            let localDate: String?
            let localDateTime: String?
            let closePrice: NaverNumber?
            let currentPrice: NaverNumber?
            let openPrice: NaverNumber?
            let highPrice: NaverNumber?
            let lowPrice: NaverNumber?
            let accumulatedTradingVolume: NaverNumber?
        }
        let rows: [Row]
        do {
            rows = try JSONDecoder().decode([Row].self, from: data)
        } catch {
            throw ProviderError.badResponse("naver candles: \(error.localizedDescription)")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Market.kr.timeZone
        formatter.dateFormat = intraday ? "yyyyMMddHHmmss" : "yyyyMMdd"

        return rows.compactMap { row -> Candle? in
            guard let stamp = intraday ? row.localDateTime : row.localDate,
                  let time = formatter.date(from: stamp),
                  let close = (row.closePrice ?? row.currentPrice)?.positive,
                  let open = row.openPrice?.positive,
                  let high = row.highPrice?.positive,
                  let low = row.lowPrice?.positive
            else { return nil }
            return Candle(
                time: time, open: open, high: high, low: low, close: close,
                volume: row.accumulatedTradingVolume?.positive
            )
        }
        .sorted { $0.time < $1.time }
    }

    /// `2026-08-20T12:12:37.828638+09:00`, and sometimes without the fraction.
    /// The sub-second digits vary in length, which is more than
    /// `ISO8601DateFormatter` will accept, so they are dropped before parsing.
    static func timestamp(from raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = trimmed
        if let dot = trimmed.firstIndex(of: "."),
           let offset = trimmed[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            text = String(trimmed[trimmed.startIndex..<dot]) + String(trimmed[offset...])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

// MARK: - Wire types

struct NaverQuoteResponse: Decodable {
    /// Every price arrives twice: once unformatted as `…Raw`, once spelled for a
    /// Korean reader. The formatted spelling is not always a number — index
    /// volume reads `185,774천주`, thousands of shares — so `…Raw` is preferred
    /// and the other kept only as a fallback for payloads that omit it.
    struct Row: Decodable {
        let itemCode: String
        let stockName: String?
        let localTradedAt: String?
        let closePrice: NaverNumber?
        let closePriceRaw: NaverNumber?
        let compareToPreviousClosePrice: NaverNumber?
        let compareToPreviousClosePriceRaw: NaverNumber?
        let openPrice: NaverNumber?
        let openPriceRaw: NaverNumber?
        let highPrice: NaverNumber?
        let highPriceRaw: NaverNumber?
        let lowPrice: NaverNumber?
        let lowPriceRaw: NaverNumber?
        let accumulatedTradingVolume: NaverNumber?
        let accumulatedTradingVolumeRaw: NaverNumber?
        let accumulatedTradingValue: NaverNumber?
        let accumulatedTradingValueRaw: NaverNumber?

        var close: Double? { (closePriceRaw ?? closePrice)?.value }
        var change: Double? { (compareToPreviousClosePriceRaw ?? compareToPreviousClosePrice)?.value }
        var open: Double? { (openPriceRaw ?? openPrice)?.positive }
        var high: Double? { (highPriceRaw ?? highPrice)?.positive }
        var low: Double? { (lowPriceRaw ?? lowPrice)?.positive }
        var volume: Double? { (accumulatedTradingVolumeRaw ?? accumulatedTradingVolume)?.positive }
        var turnover: Double? { (accumulatedTradingValueRaw ?? accumulatedTradingValue)?.positive }
    }
    let datas: [Row]?
}

/// Naver mixes numbers and their string spellings across payloads — the same
/// field is `268500` on one endpoint and `"268,500"` on another — so every
/// numeric field is read through this.
struct NaverNumber: Decodable, Sendable {
    let value: Double?

    var positive: Double? { value.flatMap { $0 > 0 ? $0 : nil } }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text.replacingOccurrences(of: ",", with: ""))
        } else {
            value = nil
        }
    }
}
