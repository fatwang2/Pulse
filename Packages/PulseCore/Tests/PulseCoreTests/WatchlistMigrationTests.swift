import Foundation
import Testing
@testable import PulseCore

@Suite("Watchlist persistence migration")
struct WatchlistMigrationTests {
    private struct LegacySymbol: Codable {
        var market: Market
        var code: String
    }

    private struct LegacyWatchItem: Codable {
        var symbol: LegacySymbol
        var displayName: String
        var addedAt: Date
        var lots: [CostLot]
    }

    @MainActor
    @Test("Legacy BTC-USD watchlist and manual order migrate without losing positions")
    func legacyCryptoWatchlist() throws {
        let suiteName = "WatchlistMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacySymbol = LegacySymbol(market: .crypto, code: "BTC-USD")
        let lot = CostLot(price: 50_000, quantity: 0.25)
        let legacyItem = LegacyWatchItem(
            symbol: legacySymbol,
            displayName: "Bitcoin USD",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lots: [lot]
        )
        defaults.set(try JSONEncoder().encode([legacyItem]), forKey: "pulse.watchlist.v1")
        defaults.set(try JSONEncoder().encode([legacySymbol]), forKey: "pulse.watchlist.manualOrder.v1")

        let store = WatchlistStore(defaults: defaults)
        let migrated = try #require(store.items.first)

        #expect(migrated.symbol == SymbolID(cryptoBase: "BTC", quote: "USDT"))
        #expect(migrated.displayName == "Bitcoin USD")
        #expect(migrated.lots == [lot])
        #expect(store.restoreManualOrder())

        let storedWatchlist = try #require(defaults.data(forKey: "pulse.watchlist.v1"))
        let storedItems = try JSONDecoder().decode([WatchItem].self, from: storedWatchlist)
        #expect(storedItems.first?.symbol.cryptoPair?.quoteAsset == "USDT")

        let storedOrder = try #require(defaults.data(forKey: "pulse.watchlist.manualOrder.v1"))
        let orderObject = try #require(JSONSerialization.jsonObject(with: storedOrder) as? [[String: Any]])
        #expect(orderObject.first?["code"] == nil)
        #expect((orderObject.first?["cryptoPair"] as? [String: String])?["quoteAsset"] == "USDT")
    }
}
