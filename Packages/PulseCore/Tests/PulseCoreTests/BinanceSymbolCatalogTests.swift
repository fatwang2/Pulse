import Foundation
import Testing
@testable import PulseCore

private actor BinanceCatalogFixture {
    private(set) var requestCount = 0
    var symbols: [BinanceExchangeSymbol]

    init(symbols: [BinanceExchangeSymbol]) {
        self.symbols = symbols
    }

    func fetch() -> [BinanceExchangeSymbol] {
        requestCount += 1
        return symbols
    }

    func replace(with symbols: [BinanceExchangeSymbol]) {
        self.symbols = symbols
    }
}

@Suite("Binance symbol catalog")
struct BinanceSymbolCatalogTests {
    private static let bitcoinUSDT = BinanceExchangeSymbol(
        symbol: "BTCUSDT", status: "TRADING", baseAsset: "BTC", quoteAsset: "USDT"
    )
    private static let bitcoinUSDC = BinanceExchangeSymbol(
        symbol: "BTCUSDC", status: "TRADING", baseAsset: "BTC", quoteAsset: "USDC"
    )
    private static let bitcoinETH = BinanceExchangeSymbol(
        symbol: "BTCETH", status: "BREAK", baseAsset: "BTC", quoteAsset: "ETH"
    )
    private static let ethereumUSDT = BinanceExchangeSymbol(
        symbol: "ETHUSDT", status: "TRADING", baseAsset: "ETH", quoteAsset: "USDT"
    )

    @Test("Search normalizes pair syntax, ranks USDT first, and excludes inactive symbols")
    func searchAndRanking() async throws {
        let fixture = BinanceCatalogFixture(symbols: [
            Self.bitcoinUSDC, Self.bitcoinETH, Self.ethereumUSDT, Self.bitcoinUSDT,
        ])
        let catalog = BinanceSymbolCatalog(cacheURL: nil) { await fixture.fetch() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let baseResults = try await catalog.search("btc", now: now)
        let pairResults = try await catalog.search("btc/usdc", now: now)

        #expect(baseResults.map(\.symbol) == [
            SymbolID(cryptoBase: "BTC", quote: "USDT"),
            SymbolID(cryptoBase: "BTC", quote: "USDC"),
        ])
        #expect(pairResults.map(\.symbol) == [SymbolID(cryptoBase: "BTC", quote: "USDC")])
        #expect(await fixture.requestCount == 1)
    }

    @Test("A fresh disk snapshot is reused without another request")
    func diskCacheReuse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = directory.appendingPathComponent("catalog.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let firstFixture = BinanceCatalogFixture(symbols: [Self.bitcoinUSDT])
        let first = BinanceSymbolCatalog(cacheURL: cacheURL) { await firstFixture.fetch() }
        _ = try await first.search("btc", now: now)

        let secondFixture = BinanceCatalogFixture(symbols: [Self.ethereumUSDT])
        let second = BinanceSymbolCatalog(cacheURL: cacheURL) { await secondFixture.fetch() }
        let cached = try await second.search("btc", now: now.addingTimeInterval(60))

        #expect(cached.map(\.symbol) == [SymbolID(cryptoBase: "BTC", quote: "USDT")])
        #expect(await secondFixture.requestCount == 0)
    }

    @Test("The catalog refreshes at 24 hours, not on every launch")
    func dailyTTL() async throws {
        let fixture = BinanceCatalogFixture(symbols: [Self.bitcoinUSDT])
        let catalog = BinanceSymbolCatalog(cacheURL: nil) { await fixture.fetch() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try await catalog.refreshIfNeeded(now: now)
        try await catalog.refreshIfNeeded(now: now.addingTimeInterval(23 * 60 * 60))
        #expect(await fixture.requestCount == 1)

        await fixture.replace(with: [Self.ethereumUSDT])
        try await catalog.refreshIfNeeded(now: now.addingTimeInterval(24 * 60 * 60))
        let ethereum = try await catalog.search("eth", now: now.addingTimeInterval(24 * 60 * 60))

        #expect(await fixture.requestCount == 2)
        #expect(ethereum.map(\.symbol) == [SymbolID(cryptoBase: "ETH", quote: "USDT")])
    }

    @Test("An empty exact search refreshes a catalog older than one hour")
    func refreshOnMiss() async throws {
        let fixture = BinanceCatalogFixture(symbols: [Self.bitcoinUSDT])
        let catalog = BinanceSymbolCatalog(cacheURL: nil) { await fixture.fetch() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await catalog.search("btc", now: now)

        await fixture.replace(with: [
            Self.bitcoinUSDT,
            BinanceExchangeSymbol(
                symbol: "DOGEUSDT", status: "TRADING", baseAsset: "DOGE", quoteAsset: "USDT"
            ),
        ])
        let doge = try await catalog.search("doge", now: now.addingTimeInterval(3_601))

        #expect(doge.map(\.symbol) == [SymbolID(cryptoBase: "DOGE", quote: "USDT")])
        #expect(await fixture.requestCount == 2)
    }

    @Test("Binance declares search capability")
    func descriptorIncludesSearch() {
        #expect(BinanceProvider().descriptor.capabilities.contains(.search))
    }
}
