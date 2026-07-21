import Foundation
import Testing
@testable import PulseCore

/// Provider contract tests: every data source (built-in or future plugin) must pass the same set of assertions.
/// They hit the real network and are skipped by default; enable with `PULSE_LIVE_TESTS=1 swift test`.
@Suite("Provider contract (live)", .enabled(if: ProcessInfo.processInfo.environment["PULSE_LIVE_TESTS"] == "1"))
struct ProviderContractTests {
    static let testSymbols = [
        SymbolID(market: .us, code: "AAPL"),
        SymbolID(market: .hk, code: "700"),
        SymbolID(market: .sh, code: "600519"),
    ]

    static func assertQuoteContract(_ quote: Quote) {
        #expect(quote.price > 0, "Price must be positive")
        #expect(quote.previousClose > 0, "Previous close must be positive")
        #expect(abs(quote.changePercent) < 50, "Single-day change should not exceed ±50% (data sanity check)")
        if let high = quote.high, let low = quote.low {
            #expect(high >= low, "High must be >= low")
        }
        #expect(quote.timestamp <= Date.now.addingTimeInterval(3600), "Timestamp should not be in the future")
    }

    static func assertCandleContract(_ candles: [Candle]) {
        #expect(!candles.isEmpty, "Candles should not be empty")
        for candle in candles {
            #expect(candle.high >= candle.low)
            #expect(candle.high >= max(candle.open, candle.close) - 0.0001)
            #expect(candle.low <= min(candle.open, candle.close) + 0.0001)
        }
        // Ascending time order
        let times = candles.map(\.time)
        #expect(times == times.sorted(), "Candles must be in ascending time order")
    }

    @Test("Tencent: batch quotes")
    func tencentQuotes() async throws {
        let quotes = try await TencentProvider().quotes(for: Self.testSymbols)
        #expect(quotes.count == Self.testSymbols.count)
        for quote in quotes { Self.assertQuoteContract(quote) }
    }

    @Test("Tencent: A-share intraday")
    func tencentIntraday() async throws {
        let candles = try await TencentProvider().candles(
            for: SymbolID(market: .sh, code: "600519"), period: .minute1, count: 60
        )
        Self.assertCandleContract(candles)
        #expect(candles.count <= 60)
    }

    @Test("Yahoo: quotes")
    func yahooQuotes() async throws {
        let quotes = try await YahooProvider().quotes(for: [SymbolID(market: .hk, code: "700")])
        #expect(quotes.count == 1)
        for quote in quotes { Self.assertQuoteContract(quote) }
    }

    @Test("Yahoo: candles", arguments: [CandlePeriod.day, .week])
    func yahooCandles(period: CandlePeriod) async throws {
        let candles = try await YahooProvider().candles(
            for: SymbolID(market: .us, code: "AAPL"), period: period, count: 60)
        Self.assertCandleContract(candles)
        #expect(candles.count <= 60)
    }

    @Test("Yahoo: search")
    func yahooSearch() async throws {
        let results = try await YahooProvider().search("tencent")
        #expect(results.contains { $0.symbol == SymbolID(market: .hk, code: "700") })
    }

    @Test("Binance: crypto quotes and candles")
    func binanceCrypto() async throws {
        let provider = BinanceProvider()
        let bitcoin = SymbolID(cryptoBase: "BTC", quote: "USDT")
        let quote = try #require(try await provider.quotes(for: [bitcoin]).first)
        Self.assertQuoteContract(quote)

        let candles = try await provider.candles(for: bitcoin, period: .minute1, count: 5)
        Self.assertCandleContract(candles)
        #expect(candles.count <= 5)
    }

    @Test("Binance: symbol catalog search")
    func binanceSearch() async throws {
        let results = try await BinanceProvider().search("BTC/USDT")
        #expect(results.first?.symbol == SymbolID(cryptoBase: "BTC", quote: "USDT"))
    }

    @Test("Binance: crypto WebSocket stream")
    func binanceCryptoStream() async throws {
        struct StreamEnded: Error {}
        struct TimedOut: Error {}

        let bitcoin = SymbolID(cryptoBase: "BTC", quote: "USDT")
        let stream = try #require(BinanceProvider().quoteStream(for: [bitcoin]))
        let quote = try await withThrowingTaskGroup(of: Quote.self) { group in
            group.addTask {
                for try await quote in stream { return quote }
                throw StreamEnded()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(12))
                throw TimedOut()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        Self.assertQuoteContract(quote)
        #expect(quote.symbol == bitcoin)
    }

    @Test("Composite: routing and merging")
    func composite() async throws {
        let composite = CompositeProvider(providers: [BinanceProvider(), TencentProvider(), YahooProvider()])
        let quotes = try await composite.quotes(for: Self.testSymbols)
        #expect(quotes.count == Self.testSymbols.count)
        let candles = try await composite.candles(for: Self.testSymbols[0], period: .day, count: 30)
        Self.assertCandleContract(candles)
    }

    @Test("Composite: stock search")
    func compositeSearch() async throws {
        let composite = CompositeProvider(providers: [BinanceProvider(), TencentProvider(), YahooProvider()])
        let results = try await composite.search("AAPL")

        #expect(results.contains { $0.symbol == SymbolID(market: .us, code: "AAPL") })
    }
}
