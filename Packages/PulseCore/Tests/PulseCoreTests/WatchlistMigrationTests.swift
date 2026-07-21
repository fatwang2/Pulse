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

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let migrated = try #require(store.items.first)

        #expect(store.groups.count == 1)
        #expect(store.selectedGroup?.name == "自选")
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

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        #expect(reloaded.groups.count == 1)
        #expect(reloaded.items.first?.lots == [lot])
        #expect(reloaded.selectedGroup?.name == "自选")
    }

    @MainActor
    @Test("A symbol can belong to several groups without duplicating its position")
    func sharedMembership() throws {
        let suiteName = "WatchlistGroupsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let apple = SymbolInfo(symbol: SymbolID(market: .us, code: "AAPL"), name: "Apple")
        store.add(apple)
        store.updateLots(apple.symbol, lots: [CostLot(price: 200, quantity: 3)])
        let defaultGroupID = try #require(store.selectedGroupID)

        let techGroupID = try #require(store.createGroup(named: "科技"))
        store.add(apple)

        #expect(store.allItems.count == 1)
        #expect(store.item(for: apple.symbol)?.positionQuantity == 3)
        #expect(store.contains(apple.symbol, in: defaultGroupID))
        #expect(store.contains(apple.symbol, in: techGroupID))

        store.selectGroup(defaultGroupID)
        #expect(store.items.map(\.symbol) == [apple.symbol])
        store.selectGroup(techGroupID)
        #expect(store.items.map(\.symbol) == [apple.symbol])
    }

    @MainActor
    @Test("Deleting a tag rehomes orphaned symbols and preserves positions")
    func deletingGroupPreservesItems() throws {
        let suiteName = "WatchlistGroupsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let defaultGroupID = try #require(store.selectedGroupID)
        let hkGroupID = try #require(store.createGroup(named: "港股"))
        let tencent = SymbolInfo(symbol: SymbolID(market: .hk, code: "700"), name: "腾讯控股")
        let lots = [CostLot(price: 400, quantity: 100)]
        store.add(tencent)
        store.updateLots(tencent.symbol, lots: lots)

        #expect(store.deleteGroup(hkGroupID))
        #expect(store.groups.count == 1)
        #expect(store.selectedGroupID == defaultGroupID)
        #expect(store.contains(tencent.symbol, in: defaultGroupID))
        #expect(store.item(for: tencent.symbol)?.lots == lots)

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        #expect(reloaded.selectedGroupID == defaultGroupID)
        #expect(reloaded.items.map(\.symbol) == [tencent.symbol])
        #expect(reloaded.item(for: tencent.symbol)?.lots == lots)
    }

    @MainActor
    @Test("Adding from search targets the selected group")
    func addTargetsSelectedGroup() throws {
        let suiteName = "WatchlistGroupsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let defaultGroupID = try #require(store.selectedGroupID)
        let usGroupID = try #require(store.createGroup(named: "美股"))
        let apple = SymbolInfo(symbol: SymbolID(market: .us, code: "AAPL"), name: "Apple")
        store.add(apple)

        #expect(store.contains(apple.symbol, in: usGroupID))
        #expect(!store.contains(apple.symbol, in: defaultGroupID))
        #expect(store.selectedGroupID == usGroupID)
    }

    @MainActor
    @Test("Tags can be reordered and keep their selection after reload")
    func reorderGroups() throws {
        let suiteName = "WatchlistGroupsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let defaultGroupID = try #require(store.selectedGroupID)
        let hkGroupID = try #require(store.createGroup(named: "港股"))
        let usGroupID = try #require(store.createGroup(named: "美股"))

        store.moveGroup(defaultGroupID, relativeTo: usGroupID)

        #expect(store.groups.map(\.id) == [hkGroupID, usGroupID, defaultGroupID])
        #expect(store.selectedGroupID == usGroupID)

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        #expect(reloaded.groups.map(\.id) == [hkGroupID, usGroupID, defaultGroupID])
        #expect(reloaded.selectedGroupID == usGroupID)
    }
}
