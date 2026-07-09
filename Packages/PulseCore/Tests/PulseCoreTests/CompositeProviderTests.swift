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
    var quotePrice: Double = 100
    var delay: [Market: TimeInterval] = [:]

    var descriptor: ProviderDescriptor {
        ProviderDescriptor(id: id, name: id, markets: Set(Market.allCases),
                           capabilities: [.search, .quotes, .candles],
                           delay: delay)
    }

    func search(_ query: String) async throws -> [SymbolInfo] {
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
}

@Suite("Composite circuit breaking and disabling")
struct CompositeProviderTests {
    static let apple = SymbolInfo(symbol: SymbolID(market: .us, code: "AAPL"), name: "Apple")

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
}
