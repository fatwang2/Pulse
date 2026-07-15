import Foundation

/// Public Binance Spot market data for crypto pairs. The provider converts Pulse's
/// structured base/quote identity to Binance's concatenated wire symbol.
public struct BinanceProvider: QuoteProvider {
    public static let providerID = "binance"

    private let http: HTTPClient
    private let restBaseURL: URL
    private let streamBaseURL: URL
    private let streamSession: URLSession
    private let symbolCatalog: BinanceSymbolCatalog

    public init(
        http: HTTPClient = HTTPClient(),
        restBaseURL: URL = URL(string: "https://data-api.binance.vision")!,
        streamBaseURL: URL = URL(string: "wss://data-stream.binance.vision")!,
        streamSession: URLSession? = nil,
        symbolCatalogCacheURL: URL? = nil,
        symbolCatalogTTL: TimeInterval = 24 * 60 * 60
    ) {
        self.http = http
        self.restBaseURL = restBaseURL
        self.streamBaseURL = streamBaseURL
        if let streamSession {
            self.streamSession = streamSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            self.streamSession = URLSession(configuration: configuration)
        }
        self.symbolCatalog = BinanceSymbolCatalog(
            cacheURL: symbolCatalogCacheURL ?? BinanceSymbolCatalog.defaultCacheURL(),
            ttl: symbolCatalogTTL
        ) {
            var components = URLComponents(
                url: restBaseURL.appendingPathComponent("api/v3/exchangeInfo"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "permissions", value: "SPOT"),
                URLQueryItem(name: "symbolStatus", value: "TRADING"),
                URLQueryItem(name: "showPermissionSets", value: "false"),
            ]
            let data = try await http.get(components.url!)
            return try Self.decode(BinanceExchangeInfoResponse.self, from: data).symbols
        }
    }

    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: Self.providerID,
            name: PulseLocalization.localizedString("provider.binance"),
            markets: [.crypto],
            capabilities: [.search, .quotes, .candles, .streaming],
            delay: [.crypto: 0],
            rateLimit: RateLimitPolicy(minInterval: 0.1, batchSize: 100),
            // WebSocket ticks are primary while the popover is open; REST polling is reconciliation.
            suggestedPollInterval: 60
        )
    }

    public func search(_ query: String) async throws -> [SymbolInfo] {
        try await symbolCatalog.search(query)
    }

    public func refreshSymbolCatalogIfNeeded() async throws {
        try await symbolCatalog.refreshIfNeeded()
    }

    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        let mapped = Self.mappedSymbols(symbols)
        guard !mapped.isEmpty else { return [] }

        var result: [Quote] = []
        for batch in Array(mapped.keys).chunked(into: 100) {
            var components = URLComponents(
                url: restBaseURL.appendingPathComponent("api/v3/ticker/24hr"),
                resolvingAgainstBaseURL: false
            )!
            let encoded = try JSONEncoder().encode(batch)
            components.queryItems = [
                URLQueryItem(name: "symbols", value: String(decoding: encoded, as: UTF8.self)),
                URLQueryItem(name: "symbolStatus", value: "TRADING"),
            ]
            let data: Data
            do {
                data = try await http.get(components.url!)
            } catch ProviderError.clientError(400, _) {
                await symbolCatalog.refreshAfterSymbolFailure()
                throw ProviderError.symbolNotFound(mapped.values.first!.first!)
            }
            let tickers = try Self.decode([BinanceTicker24Hour].self, from: data)
            for ticker in tickers {
                for symbol in mapped[ticker.symbol] ?? [] {
                    if let quote = Self.quote(from: ticker, symbol: symbol) {
                        result.append(quote)
                    }
                }
            }
        }
        return symbols.compactMap { symbol in result.first(where: { $0.symbol == symbol }) }
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard let binanceSymbol = Self.binanceSymbol(for: symbol) else {
            throw ProviderError.symbolNotFound(symbol)
        }
        var components = URLComponents(
            url: restBaseURL.appendingPathComponent("api/v3/klines"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: binanceSymbol),
            URLQueryItem(name: "interval", value: Self.interval(for: period)),
            URLQueryItem(name: "limit", value: String(max(1, min(count, 1_000)))),
        ]
        let data: Data
        do {
            data = try await http.get(components.url!)
        } catch ProviderError.clientError(400, _) {
            await symbolCatalog.refreshAfterSymbolFailure()
            throw ProviderError.symbolNotFound(symbol)
        }
        return try Self.decode([BinanceKline].self, from: data).map(\.candle)
    }

    public func quoteStream(for symbols: [SymbolID]) -> AsyncThrowingStream<Quote, any Error>? {
        let mapped = Self.mappedSymbols(symbols)
        guard !mapped.isEmpty else { return nil }

        let streamNames = mapped.keys.sorted().map { "\($0.lowercased())@ticker" }
        var components = URLComponents(
            url: streamBaseURL.appendingPathComponent("stream"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "streams", value: streamNames.joined(separator: "/"))]
        guard let url = components.url else { return nil }

        return AsyncThrowingStream { continuation in
            let socket = streamSession.webSocketTask(with: url)
            let receiveTask = Task {
                socket.resume()
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case .data(let value): data = value
                        case .string(let string): data = Data(string.utf8)
                        @unknown default: continue
                        }
                        let event = try Self.decode(BinanceCombinedTickerStream.self, from: data)
                        for symbol in mapped[event.data.symbol] ?? [] {
                            if let quote = Self.quote(from: event.data, symbol: symbol) {
                                continuation.yield(quote)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ProviderError.network(underlying: error.localizedDescription))
                }
                socket.cancel(with: .goingAway, reason: nil)
            }
            continuation.onTermination = { _ in
                receiveTask.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    // MARK: - Mapping and parsing

    static func binanceSymbol(for symbol: SymbolID) -> String? {
        guard let pair = symbol.cryptoPair else { return nil }
        let base = pair.baseAsset
        let quote = pair.quoteAsset
        guard !base.isEmpty, !quote.isEmpty,
              (base + quote).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return nil
        }
        return base + quote
    }

    static func mappedSymbols(_ symbols: [SymbolID]) -> [String: [SymbolID]] {
        Dictionary(grouping: symbols.compactMap { symbol in
            Self.binanceSymbol(for: symbol).map { ($0, symbol) }
        }, by: \.0).mapValues { $0.map(\.1) }
    }

    static func interval(for period: CandlePeriod) -> String {
        switch period {
        case .minute1: "1m"
        case .minute5: "5m"
        case .day: "1d"
        case .week: "1w"
        case .month: "1M"
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ProviderError.badResponse("binance decode: \(error.localizedDescription)")
        }
    }

    static func quote(from ticker: BinanceTicker24Hour, symbol: SymbolID) -> Quote? {
        guard let price = Double(ticker.lastPrice),
              let previousClose = Double(ticker.prevClosePrice),
              price > 0, previousClose > 0 else { return nil }
        return Quote(
            symbol: symbol,
            price: price,
            previousClose: previousClose,
            open: Double(ticker.openPrice),
            high: Double(ticker.highPrice),
            low: Double(ticker.lowPrice),
            volume: Double(ticker.volume),
            turnover: Double(ticker.quoteVolume),
            currencyCode: Self.quoteCurrency(for: symbol),
            timestamp: Date(timeIntervalSince1970: Double(ticker.closeTime) / 1_000),
            marketState: .regular
        )
    }

    static func quote(from ticker: BinanceStreamTicker, symbol: SymbolID) -> Quote? {
        guard let price = Double(ticker.lastPrice),
              let previousClose = Double(ticker.previousClose),
              price > 0, previousClose > 0 else { return nil }
        return Quote(
            symbol: symbol,
            price: price,
            previousClose: previousClose,
            open: Double(ticker.openPrice),
            high: Double(ticker.highPrice),
            low: Double(ticker.lowPrice),
            volume: Double(ticker.volume),
            turnover: Double(ticker.quoteVolume),
            currencyCode: Self.quoteCurrency(for: symbol),
            timestamp: Date(timeIntervalSince1970: Double(ticker.closeTime) / 1_000),
            marketState: .regular
        )
    }

    private static func quoteCurrency(for symbol: SymbolID) -> String? {
        symbol.cryptoPair?.quoteAsset
    }
}

struct BinanceTicker24Hour: Decodable {
    let symbol: String
    let prevClosePrice: String
    let lastPrice: String
    let openPrice: String
    let highPrice: String
    let lowPrice: String
    let volume: String
    let quoteVolume: String
    let closeTime: Int64
}

struct BinanceCombinedTickerStream: Decodable {
    let stream: String
    let data: BinanceStreamTicker
}

struct BinanceStreamTicker: Decodable {
    let symbol: String
    let previousClose: String
    let lastPrice: String
    let openPrice: String
    let highPrice: String
    let lowPrice: String
    let volume: String
    let quoteVolume: String
    let closeTime: Int64

    enum CodingKeys: String, CodingKey {
        case symbol = "s"
        case previousClose = "x"
        case lastPrice = "c"
        case openPrice = "o"
        case highPrice = "h"
        case lowPrice = "l"
        case volume = "v"
        case quoteVolume = "q"
        case closeTime = "C"
    }
}

struct BinanceKline: Decodable {
    let openTime: Int64
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double?

    init(from decoder: any Decoder) throws {
        var values = try decoder.unkeyedContainer()
        openTime = try values.decode(Int64.self)
        open = try Self.decodeNumber(from: &values)
        high = try Self.decodeNumber(from: &values)
        low = try Self.decodeNumber(from: &values)
        close = try Self.decodeNumber(from: &values)
        volume = try? Self.decodeNumber(from: &values)
    }

    var candle: Candle {
        Candle(
            time: Date(timeIntervalSince1970: Double(openTime) / 1_000),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume
        )
    }

    private static func decodeNumber(from container: inout UnkeyedDecodingContainer) throws -> Double {
        let raw = try container.decode(String.self)
        guard let value = Double(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Binance number")
        }
        return value
    }
}
