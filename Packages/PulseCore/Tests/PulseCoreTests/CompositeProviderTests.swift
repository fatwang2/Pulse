import Foundation
import Testing
@testable import PulseCore

/// Programmable fake data source for verifying Composite's routing and circuit-breaking behavior
struct MockProvider: QuoteProvider {
    var id: String
    var searchError: ProviderError?
    var quoteError: ProviderError?
    var searchResults: [SymbolInfo] = []
    var candleResult: [Candle] = [Candle(time: .now, open: 1, high: 2, low: 0.5, close: 1.5)]
    var candleMarkets: Set<Market>?
    var candlePeriods: Set<CandlePeriod>?
    var quotePrice: Double = 100
    var searchDelay: Duration = .zero
    var minimumRequestInterval: TimeInterval?
    var delay: [Market: TimeInterval] = [:]
    var markets: Set<Market> = Set(Market.allCases)
    var supportsStreaming = false

    var descriptor: ProviderDescriptor {
        var capabilities: Set<Capability> = [.search, .quotes, .candles]
        if supportsStreaming { capabilities.insert(.streaming) }
        return ProviderDescriptor(id: id, name: id, markets: markets,
                           capabilities: capabilities,
                           candleMarkets: candleMarkets,
                           candlePeriods: candlePeriods,
                           delay: delay,
                           rateLimit: minimumRequestInterval.map { RateLimitPolicy(minInterval: $0) })
    }

    func search(_ query: String) async throws -> [SymbolInfo] {
        if searchDelay > .zero {
            try await Task.sleep(for: searchDelay)
        }
        if let searchError { throw searchError }
        return searchResults
    }

    func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        if let quoteError { throw quoteError }
        return symbols.map { Quote(symbol: $0, price: quotePrice, previousClose: 99) }
    }

    func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        candleResult
    }

    func quoteStream(for symbols: [SymbolID]) -> AsyncThrowingStream<Quote, any Error>? {
        guard supportsStreaming else { return nil }
        return AsyncThrowingStream { continuation in
            for symbol in symbols {
                continuation.yield(Quote(symbol: symbol, price: quotePrice, previousClose: 99))
            }
            continuation.finish()
        }
    }
}

@Suite("Composite circuit breaking and disabling")
struct CompositeProviderTests {
    static let apple = SymbolInfo(symbol: SymbolID(market: .us, code: "AAPL"), name: "Apple")

    @Test("Search providers run concurrently while results keep provider order")
    func concurrentSearchKeepsRanking() async throws {
        let tencent = SymbolInfo(symbol: SymbolID(market: .hk, code: "700"), name: "Tencent")
        let first = MockProvider(id: "first", searchResults: [Self.apple], searchDelay: .milliseconds(300))
        let second = MockProvider(id: "second", searchResults: [tencent], searchDelay: .milliseconds(300))
        let composite = CompositeProvider(providers: [first, second])
        let clock = ContinuousClock()

        let startedAt = clock.now
        let results = try await composite.search("tech")
        let elapsed = startedAt.duration(to: clock.now)

        #expect(results == [Self.apple, tencent])
        #expect(elapsed < .milliseconds(500))
    }

    @Test("A stalled source cannot hold useful search results")
    func stalledSourceReturnsPartialResults() async throws {
        let fast = MockProvider(id: "fast", searchResults: [Self.apple])
        let stalled = MockProvider(
            id: "stalled",
            searchResults: [],
            searchDelay: .seconds(5)
        )
        let composite = CompositeProvider(
            providers: [fast, stalled],
            searchResultSettleDelay: .milliseconds(50),
            searchDeadline: .milliseconds(200)
        )
        let clock = ContinuousClock()

        let startedAt = clock.now
        let results = try await composite.search("apple")
        let elapsed = startedAt.duration(to: clock.now)

        #expect(results == [Self.apple])
        #expect(elapsed < .milliseconds(180))
    }

    @Test("Search fails by its deadline when no source responds")
    func stalledSearchHasHardDeadline() async {
        let stalled = MockProvider(
            id: "stalled",
            searchResults: [],
            searchDelay: .seconds(5)
        )
        let composite = CompositeProvider(
            providers: [stalled],
            searchResultSettleDelay: .milliseconds(50),
            searchDeadline: .milliseconds(100)
        )
        let clock = ContinuousClock()

        let startedAt = clock.now
        await #expect(throws: ProviderError.self) {
            _ = try await composite.search("apple")
        }
        let elapsed = startedAt.duration(to: clock.now)

        #expect(elapsed < .milliseconds(250))
    }

    @Test("Cancelling a throttled search does not delay the next query")
    func cancelledSearchDoesNotReserveFutureBudget() async throws {
        let limited = MockProvider(
            id: "limited",
            searchResults: [Self.apple],
            minimumRequestInterval: 0.4
        )
        let composite = CompositeProvider(
            providers: [limited],
            searchDeadline: .seconds(2)
        )
        _ = try await composite.search("first")

        let cancelled = Task { try await composite.search("second") }
        try await Task.sleep(for: .milliseconds(40))
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            Issue.record("Cancelled search should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        _ = try await composite.search("third")
        let elapsed = startedAt.duration(to: clock.now)

        #expect(elapsed < .milliseconds(650))
    }

    @Test("4xx client errors don't trip the circuit: candles still work after a 400 from search")
    func clientErrorDoesNotTrip() async throws {
        let flaky = MockProvider(id: "flaky",
                                 searchError: .clientError(status: 400, detail: "Invalid Search Query"))
        let composite = CompositeProvider(providers: [flaky])

        _ = try? await composite.search("腾讯")  // 400, but must not trip the circuit
        let candles = try await composite.candles(
            for: SymbolID(market: .us, code: "AAPL"), period: .day, count: 10)
        #expect(!candles.isEmpty, "flaky should not be tripped by a 400")
    }

    @Test("Network errors trip the circuit and fail over to the next source")
    func networkErrorTripsAndFailsOver() async throws {
        let dead = MockProvider(id: "dead", searchError: .network(underlying: "offline"))
        let backup = MockProvider(id: "backup", searchResults: [Self.apple])
        let composite = CompositeProvider(providers: [dead, backup])

        // Concurrent merged search: dead fails but backup has results
        let results = try await composite.search("apple")
        #expect(results == [Self.apple])

        // dead is now tripped: candles should come from backup (a normal backup response proves the failover routing works)
        let candles = try await composite.candles(
            for: SymbolID(market: .us, code: "AAPL"), period: .day, count: 10)
        #expect(!candles.isEmpty)
    }

    @Test("During cooldown, reports rateLimited (auto-recovers) rather than unsupported (user-disabled)")
    func coolingReportsRateLimited() async throws {
        let dead = MockProvider(id: "dead", searchError: .network(underlying: "offline"))
        let composite = CompositeProvider(providers: [dead])

        _ = try? await composite.search("x")  // Network error -> circuit trips
        do {
            _ = try await composite.search("x")
            Issue.record("Should throw during the cooldown period")
        } catch let error as ProviderError {
            guard case .rateLimited = error else {
                Issue.record("Expected rateLimited, got \(error)")
                return
            }
        }
    }

    @Test("Disabled sources no longer participate in routing")
    func disabledProviderExcluded() async throws {
        let only = MockProvider(id: "only", searchResults: [Self.apple])
        let composite = CompositeProvider(providers: [only], disabledIDs: ["only"])

        await #expect(throws: ProviderError.self) {
            _ = try await composite.search("apple")
        }

        // Recovers after re-enabling
        await composite.setDisabled([])
        let results = try await composite.search("apple")
        #expect(results == [Self.apple])
    }

    @Test("US quotes prefer Yahoo while other markets keep provider order")
    func usQuotesPreferYahoo() async throws {
        let tencent = MockProvider(id: "tencent", quotePrice: 100)
        let yahoo = MockProvider(id: "yahoo", quotePrice: 200)
        let composite = CompositeProvider(providers: [tencent, yahoo])
        let apple = SymbolID(market: .us, code: "AAPL")
        let tencentHK = SymbolID(market: .hk, code: "700")

        let quotes = try await composite.quotes(for: [apple, tencentHK])

        #expect(quotes.first(where: { $0.symbol == apple })?.price == 200)
        #expect(quotes.first(where: { $0.symbol == tencentHK })?.price == 100)
    }

    @Test("Crypto quotes use Binance")
    func cryptoQuotesPreferBinance() async throws {
        let yahoo = MockProvider(id: "yahoo", quotePrice: 100)
        let binance = MockProvider(id: BinanceProvider.providerID, quotePrice: 200, markets: [.crypto])
        let composite = CompositeProvider(providers: [yahoo, binance])
        let bitcoin = SymbolID(cryptoBase: "BTC", quote: "USDT")

        let quote = try #require(try await composite.quotes(for: [bitcoin]).first)

        #expect(quote.price == 200)
        #expect(quote.sourceID == BinanceProvider.providerID)
    }

    @Test("Crypto does not fall back to a different Yahoo USD instrument")
    func cryptoDoesNotFallbackToYahoo() async {
        let yahoo = MockProvider(id: "yahoo", quotePrice: 100, markets: [.us, .hk, .sh, .sz])
        let binance = MockProvider(
            id: BinanceProvider.providerID,
            quoteError: .network(underlying: "offline"),
            markets: [.crypto]
        )
        let composite = CompositeProvider(providers: [binance, yahoo])
        let bitcoin = SymbolID(cryptoBase: "BTC", quote: "USDT")

        await #expect(throws: ProviderError.self) {
            _ = try await composite.quotes(for: [bitcoin])
        }
    }

    @Test("Streaming sources are merged by market")
    func streamingRoutesByMarket() async throws {
        let longbridge = MockProvider(
            id: LongbridgeProvider.providerID,
            quotePrice: 100,
            markets: [.us, .hk, .sh, .sz],
            supportsStreaming: true
        )
        let binance = MockProvider(
            id: BinanceProvider.providerID,
            quotePrice: 200,
            markets: [.crypto],
            supportsStreaming: true
        )
        let composite = CompositeProvider(providers: [longbridge, binance])
        let apple = SymbolID(market: .us, code: "AAPL")
        let bitcoin = SymbolID(cryptoBase: "BTC", quote: "USDT")
        let stream = try #require(composite.quoteStream(for: [apple, bitcoin]))
        var received: [Quote] = []

        for try await quote in stream { received.append(quote) }

        #expect(received.count == 2)
        #expect(received.first(where: { $0.symbol == apple })?.sourceID == LongbridgeProvider.providerID)
        #expect(received.first(where: { $0.symbol == bitcoin })?.sourceID == BinanceProvider.providerID)
    }

    @Test("Quotes are annotated with the actual source and its market delay")
    func quotesCarrySourceMetadata() async throws {
        let tencent = MockProvider(id: "tencent",
                                   quoteError: .network(underlying: "offline"),
                                   delay: [.sh: 0])
        let yahoo = MockProvider(id: "yahoo", quotePrice: 200, delay: [.sh: 900])
        let composite = CompositeProvider(providers: [tencent, yahoo])
        let maotai = SymbolID(market: .sh, code: "600519")

        let quote = try #require(try await composite.quotes(for: [maotai]).first)

        #expect(quote.price == 200)
        #expect(quote.sourceID == "yahoo")
        #expect(quote.sourceName == "yahoo")
        #expect(quote.sourceDelay == 900)
    }

    @Test("A-share intraday uses the specialized source while daily and other markets use the broad source")
    func periodAwareCandleRouting() async throws {
        let intraday = MockProvider(
            id: "tencent",
            candleResult: [Candle(time: .now, open: 1, high: 1, low: 1, close: 1)],
            candleMarkets: [.sh, .sz],
            candlePeriods: [.minute1, .minute5]
        )
        let historical = MockProvider(
            id: "yahoo",
            candleResult: [Candle(time: .now, open: 2, high: 2, low: 2, close: 2)]
        )
        let composite = CompositeProvider(providers: [intraday, historical])

        let shanghai = SymbolID(market: .sh, code: "600519")
        let hongKong = SymbolID(market: .hk, code: "700")
        #expect(try await composite.candles(for: shanghai, period: .minute1, count: 10).first?.close == 1)
        #expect(try await composite.candles(for: shanghai, period: .day, count: 10).first?.close == 2)
        #expect(try await composite.candles(for: hongKong, period: .minute1, count: 10).first?.close == 2)
    }
}
