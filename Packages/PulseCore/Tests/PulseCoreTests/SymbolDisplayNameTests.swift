import Foundation
import Testing
@testable import PulseCore

@Suite("Provider-independent symbol names")
struct SymbolDisplayNameTests {
    private struct RenamingQuoteProvider: QuoteProvider {
        var descriptor: ProviderDescriptor {
            ProviderDescriptor(
                id: "renaming",
                name: "Renaming",
                markets: [.us],
                capabilities: [.quotes]
            )
        }

        func search(_ query: String) async throws -> [SymbolInfo] {
            throw ProviderError.unsupported(.search)
        }

        func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
            symbols.map {
                Quote(
                    symbol: $0,
                    name: "PDD Holdings Inc.",
                    price: 120,
                    previousClose: 118
                )
            }
        }

        func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
            []
        }
    }

    @Test("Ordinary securities retain the name captured when added")
    func securityNameIsStable() {
        let pdd = SymbolID(market: .us, code: "PDD")
        let searchResult = SymbolInfo(symbol: pdd, name: "拼多多")
        let item = WatchItem(symbol: pdd, displayName: searchResult.resolvedDisplayName)

        #expect(searchResult.resolvedDisplayName == "拼多多")
        #expect(item.resolvedDisplayName == "拼多多")
    }

    @Test("Known indices ignore provider-specific spellings")
    func indexNamesComeFromCanonicalCatalog() {
        let symbol = SymbolID(index: .sp500)
        let yahoo = SymbolInfo(symbol: symbol, name: "S&P 500")
        let tencent = WatchItem(symbol: symbol, displayName: "标普500")

        #expect(yahoo.resolvedDisplayName == MarketIndexID.sp500.displayName)
        #expect(tencent.resolvedDisplayName == MarketIndexID.sp500.displayName)
    }

    @Test("Every canonical index has a real display name")
    func indexCatalogIsComplete() {
        for index in MarketIndexID.allCases {
            #expect(!index.displayName.isEmpty)
            #expect(!index.displayName.hasPrefix("index."))
            #expect(index.displayName != index.displayCode)
        }
    }

    @MainActor
    @Test("Quote refresh cannot overwrite a saved security name")
    func quoteRefreshDoesNotRenameWatchItem() async throws {
        let suiteName = "SymbolDisplayNameTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let pdd = SymbolID(market: .us, code: "PDD")
        let watchlist = WatchlistStore(defaults: defaults, defaultGroupName: "Watchlist")
        watchlist.add(SymbolInfo(symbol: pdd, name: "拼多多"))
        let market = MarketStore()
        let composite = CompositeProvider(providers: [RenamingQuoteProvider()])
        let engine = RefreshEngine(provider: composite, store: market, watchlist: watchlist)
        engine.start()
        defer { engine.stop() }

        for _ in 0..<20 where market.quote(for: pdd) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(market.quote(for: pdd)?.name == "PDD Holdings Inc.")
        #expect(watchlist.item(for: pdd)?.displayName == "拼多多")
        #expect(watchlist.item(for: pdd)?.resolvedDisplayName == "拼多多")
    }
}
