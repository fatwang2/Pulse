import Foundation

/// Yahoo Finance v8 chart / v1 search (unofficial API).
/// Capabilities: search + quotes + candles across US/HK/SH/SZ; A-shares and HK are delayed by about 15 minutes.
public struct YahooProvider: QuoteProvider {
    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: "yahoo",
            name: "Yahoo Finance",
            markets: [.us, .hk, .sh, .sz],
            capabilities: [.search, .quotes, .candles],
            delay: [.us: 0, .hk: 900, .sh: 900, .sz: 900],
            rateLimit: RateLimitPolicy(minInterval: 5, batchSize: 1)
        )
    }

    // MARK: - Symbol mapping

    static func yahooSymbol(for id: SymbolID) -> String {
        switch id.market {
        case .us: id.code
        case .hk: id.paddedCode(width: 4) + ".HK"
        case .sh: id.code + ".SS"
        case .sz: id.code + ".SZ"
        }
    }

    static func symbolID(fromYahoo raw: String) -> SymbolID? {
        let upper = raw.uppercased()
        if upper.hasSuffix(".HK") { return SymbolID(market: .hk, code: String(upper.dropLast(3))) }
        if upper.hasSuffix(".SS") { return SymbolID(market: .sh, code: String(upper.dropLast(3))) }
        if upper.hasSuffix(".SZ") { return SymbolID(market: .sz, code: String(upper.dropLast(3))) }
        // Other exchange suffixes / FX symbols are not supported yet; no suffix means US (including indices like ^GSPC, tickers like BRK-B)
        if upper.contains(".") || upper.contains("=") { return nil }
        return SymbolID(market: .us, code: upper)
    }

    // MARK: - QuoteProvider

    public func search(_ query: String) async throws -> [SymbolInfo] {
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "quotesCount", value: "12"),
            .init(name: "newsCount", value: "0"),
            .init(name: "listsCount", value: "0"),
        ]
        let data: Data
        do {
            data = try await http.get(comps.url!)
        } catch ProviderError.clientError(400, _) {
            // Yahoo search rejects Chinese and similar queries ("Invalid Search Query") — treat as no results;
            // Chinese/pinyin search is covered by other sources (Tencent smartbox)
            return []
        }
        let decoded = try Self.decode(SearchResponse.self, from: data)
        return (decoded.quotes ?? []).compactMap { item -> SymbolInfo? in
            guard let raw = item.symbol, let id = Self.symbolID(fromYahoo: raw) else { return nil }
            let type: InstrumentType = switch item.quoteType?.uppercased() {
            case "EQUITY": .equity
            case "ETF": .etf
            case "INDEX": .index
            case "MUTUALFUND": .fund
            default: .other
            }
            guard type != .other else { return nil }
            let name = item.longname ?? item.shortname ?? raw
            return SymbolInfo(symbol: id, name: name, exchangeName: item.exchDisp, type: type)
        }
    }

    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: Result<Quote, any Error>.self) { group in
            for symbol in symbols {
                group.addTask {
                    do {
                        return .success(try await self.quote(for: symbol))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var quotes: [Quote] = []
            var sawRateLimit = false
            var lastError: (any Error)?
            for try await outcome in group {
                switch outcome {
                case .success(let quote): quotes.append(quote)
                case .failure(let error):
                    if case ProviderError.rateLimited = error { sawRateLimit = true }
                    lastError = error
                }
            }
            guard !quotes.isEmpty else {
                // When everything failed, report rate limiting truthfully (triggers a short cooldown); otherwise pass through the real error
                if sawRateLimit { throw ProviderError.rateLimited }
                throw lastError ?? ProviderError.badResponse("yahoo: all quote requests failed")
            }
            return quotes
        }
    }

    func quote(for symbol: SymbolID) async throws -> Quote {
        let result = try await chart(for: symbol, interval: "1d", range: "1d")
        let meta = result.meta
        guard let price = meta.regularMarketPrice else {
            throw ProviderError.symbolNotFound(symbol)
        }
        let prevClose = meta.previousClose ?? meta.chartPreviousClose ?? price
        let ohlc = result.indicators.quote?.first
        return Quote(
            symbol: symbol,
            name: meta.longName ?? meta.shortName,
            price: price,
            previousClose: prevClose,
            open: ohlc?.open?.compactMap(\.self).first,
            high: meta.regularMarketDayHigh,
            low: meta.regularMarketDayLow,
            volume: meta.regularMarketVolume,
            currencyCode: meta.currency,
            timestamp: meta.regularMarketTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now
        )
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        let (interval, range) = Self.chartParams(for: period)
        let result = try await chart(for: symbol, interval: interval, range: range)
        guard let timestamps = result.timestamp, let ohlc = result.indicators.quote?.first else {
            return []
        }
        var candles: [Candle] = []
        candles.reserveCapacity(timestamps.count)
        for (i, ts) in timestamps.enumerated() {
            guard let open = ohlc.open?[safe: i] ?? nil,
                  let high = ohlc.high?[safe: i] ?? nil,
                  let low = ohlc.low?[safe: i] ?? nil,
                  let close = ohlc.close?[safe: i] ?? nil else { continue }
            let volume = ohlc.volume?[safe: i] ?? nil
            candles.append(Candle(time: Date(timeIntervalSince1970: TimeInterval(ts)),
                                  open: open, high: high, low: low, close: close, volume: volume))
        }
        return Array(candles.suffix(count))
    }

    static func chartParams(for period: CandlePeriod) -> (interval: String, range: String) {
        switch period {
        case .minute1: ("1m", "1d")
        case .minute5: ("5m", "1d")
        case .day: ("1d", "1y")
        case .week: ("1wk", "5y")
        case .month: ("1mo", "max")
        }
    }

    func chart(for symbol: SymbolID, interval: String, range: String) async throws -> ChartResponse.Result {
        let ySymbol = Self.yahooSymbol(for: symbol)
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(ySymbol)")!
        comps.queryItems = [
            .init(name: "interval", value: interval),
            .init(name: "range", value: range),
            .init(name: "includePrePost", value: "false"),
        ]
        let data: Data
        do {
            data = try await http.get(comps.url!)
        } catch ProviderError.clientError(404, _) {
            // Yahoo doesn't have this symbol (e.g. A-share indices, instruments outside the HKD counter) — a coverage gap, not a source failure
            throw ProviderError.symbolNotFound(symbol)
        }
        let decoded = try Self.decode(ChartResponse.self, from: data)
        if decoded.chart.error != nil {
            // Business errors from the chart API (Not Found / No data, etc.) are likewise treated as "symbol not found" and don't trip the circuit
            throw ProviderError.symbolNotFound(symbol)
        }
        guard let result = decoded.chart.result?.first else {
            throw ProviderError.symbolNotFound(symbol)
        }
        return result
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ProviderError.badResponse("yahoo: JSON decode failed — \(error)")
        }
    }
}

// MARK: - Response models

struct ChartResponse: Decodable {
    struct Chart: Decodable {
        var result: [Result]?
        var error: ChartError?
    }
    struct ChartError: Decodable {
        var code: String?
        var description: String?
    }
    struct Result: Decodable {
        var meta: Meta
        var timestamp: [Int]?
        var indicators: Indicators
    }
    struct Meta: Decodable {
        var currency: String?
        var symbol: String
        var regularMarketPrice: Double?
        var chartPreviousClose: Double?
        var previousClose: Double?
        var regularMarketDayHigh: Double?
        var regularMarketDayLow: Double?
        var regularMarketVolume: Double?
        var regularMarketTime: Int?
        var shortName: String?
        var longName: String?
    }
    struct Indicators: Decodable {
        var quote: [QuoteArrays]?
    }
    struct QuoteArrays: Decodable {
        var open: [Double?]?
        var high: [Double?]?
        var low: [Double?]?
        var close: [Double?]?
        var volume: [Double?]?
    }
    var chart: Chart
}

struct SearchResponse: Decodable {
    struct Item: Decodable {
        var symbol: String?
        var shortname: String?
        var longname: String?
        var exchDisp: String?
        var quoteType: String?
    }
    var quotes: [Item]?
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
