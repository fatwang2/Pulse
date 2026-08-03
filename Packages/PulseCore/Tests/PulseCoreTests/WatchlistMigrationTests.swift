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

    private struct LegacyWatchlistGroup: Codable {
        var id: UUID
        var name: String
        var symbols: [LegacySymbol]
        var manualOrder: [LegacySymbol]?
    }

    private struct LegacySnapshot: Codable {
        var items: [LegacyWatchItem]
        var groups: [LegacyWatchlistGroup]
        var selectedGroupID: UUID?
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
        #expect(migrated.displayNameSource == nil)
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
    @Test("Legacy provider aliases merge into one canonical index without losing lots")
    func legacyIndexAliasesMerge() throws {
        let suiteName = "WatchlistIndexMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let yahooAlias = LegacySymbol(market: .us, code: "^GSPC")
        let longbridgeAlias = LegacySymbol(market: .us, code: "^SPX")
        let firstLot = CostLot(price: 6_000, quantity: 1)
        let secondLot = CostLot(price: 6_500, quantity: 2)
        let groupID = UUID()
        let snapshot = LegacySnapshot(
            items: [
                LegacyWatchItem(
                    symbol: yahooAlias,
                    displayName: "S&P 500",
                    addedAt: Date(timeIntervalSince1970: 100),
                    lots: [firstLot]
                ),
                LegacyWatchItem(
                    symbol: longbridgeAlias,
                    displayName: "标普500",
                    addedAt: Date(timeIntervalSince1970: 200),
                    lots: [secondLot]
                ),
            ],
            groups: [
                LegacyWatchlistGroup(
                    id: groupID,
                    name: "指数",
                    symbols: [yahooAlias, longbridgeAlias],
                    manualOrder: [longbridgeAlias, yahooAlias]
                ),
            ],
            selectedGroupID: groupID
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "pulse.watchlists.v2")

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let item = try #require(store.allItems.first)

        #expect(store.allItems.count == 1)
        #expect(item.symbol == SymbolID(index: .sp500))
        #expect(Set(item.lots.map(\.id)) == Set([firstLot.id, secondLot.id]))
        #expect(store.selectedGroup?.symbols == [SymbolID(index: .sp500)])
        #expect(store.selectedGroup?.manualOrder == [SymbolID(index: .sp500)])
        #expect(store.selectedGroup?.pinnedSymbols.isEmpty == true)

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        #expect(reloaded.allItems.first?.symbol.indexID == .sp500)
        #expect(reloaded.allItems.first?.lots.count == 2)
        #expect(reloaded.allItems.first?.supportsPosition == false)
        #expect(reloaded.selectedGroup?.pinnedSymbols.isEmpty == true)

        let replacementLot = CostLot(price: 7_000, quantity: 3)
        reloaded.updateLots(SymbolID(index: .sp500), lots: [replacementLot])
        #expect(reloaded.allItems.first?.lots.count == 2)

        reloaded.clearPosition(SymbolID(index: .sp500))
        #expect(reloaded.allItems.first?.lots.isEmpty == true)
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
    @Test("Pinned symbols persist per group and are cleared with membership")
    func pinnedSymbolsAreGroupScoped() throws {
        let suiteName = "WatchlistPinnedSymbolsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let apple = SymbolInfo(symbol: SymbolID(market: .us, code: "AAPL"), name: "Apple")
        let microsoft = SymbolInfo(symbol: SymbolID(market: .us, code: "MSFT"), name: "Microsoft")
        store.add(apple)
        store.add(microsoft)
        let defaultGroupID = try #require(store.selectedGroupID)
        #expect(store.setPinned(apple.symbol, pinned: true))

        let techGroupID = try #require(store.createGroup(named: "科技"))
        store.add(apple)
        store.add(microsoft)
        #expect(store.setPinned(microsoft.symbol, pinned: true))
        #expect(!store.setPinned(microsoft.symbol, pinned: true))

        #expect(store.isPinned(apple.symbol, in: defaultGroupID))
        #expect(!store.isPinned(microsoft.symbol, in: defaultGroupID))
        #expect(!store.isPinned(apple.symbol, in: techGroupID))
        #expect(store.isPinned(microsoft.symbol, in: techGroupID))

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        #expect(reloaded.isPinned(apple.symbol, in: defaultGroupID))
        #expect(reloaded.isPinned(microsoft.symbol, in: techGroupID))

        reloaded.setMembership(microsoft.symbol, in: techGroupID, included: false)
        #expect(!reloaded.isPinned(microsoft.symbol, in: techGroupID))
        #expect(!reloaded.setPinned(microsoft.symbol, in: techGroupID, pinned: true))
        #expect(reloaded.item(for: microsoft.symbol) != nil)
        reloaded.setMembership(microsoft.symbol, in: techGroupID, included: true)
        #expect(!reloaded.isPinned(microsoft.symbol, in: techGroupID))
    }

    @MainActor
    @Test("New members lead the unpinned section and keep that baseline after reload")
    func newMembersLeadUnpinnedSection() throws {
        let suiteName = "WatchlistNewMemberOrderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let apple = SymbolInfo(symbol: SymbolID(market: .us, code: "AAPL"), name: "Apple")
        let microsoft = SymbolInfo(symbol: SymbolID(market: .us, code: "MSFT"), name: "Microsoft")
        let tesla = SymbolInfo(symbol: SymbolID(market: .us, code: "TSLA"), name: "Tesla")

        store.add(apple)
        store.add(microsoft)
        #expect(store.items.map(\.symbol) == [microsoft.symbol, apple.symbol])
        store.add(microsoft)
        #expect(store.items.map(\.symbol) == [microsoft.symbol, apple.symbol])

        store.reorder([apple.symbol, microsoft.symbol])
        store.rememberManualOrder()
        #expect(store.setPinned(microsoft.symbol, pinned: true))
        _ = store.restoreManualOrder()
        store.reorder([microsoft.symbol])

        store.add(tesla)
        #expect(store.items.map(\.symbol) == [microsoft.symbol, tesla.symbol, apple.symbol])
        #expect(store.selectedGroup?.manualOrder == [tesla.symbol, apple.symbol, microsoft.symbol])

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        #expect(reloaded.items.map(\.symbol) == [microsoft.symbol, tesla.symbol, apple.symbol])
        #expect(reloaded.selectedGroup?.manualOrder == [tesla.symbol, apple.symbol, microsoft.symbol])

        reloaded.rememberManualOrder()
        #expect(reloaded.setPinned(microsoft.symbol, pinned: false))
        #expect(reloaded.restoreManualOrder())
        #expect(reloaded.items.map(\.symbol) == [tesla.symbol, apple.symbol, microsoft.symbol])
    }

    @MainActor
    @Test("New members do not replace the hidden custom order with the automatic presentation")
    func newMembersPreserveHiddenCustomOrder() throws {
        let suiteName = "WatchlistNewMemberAutomaticOrderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let symbols = ["AAPL", "MSFT", "TSLA", "ONDS"].map {
            SymbolInfo(symbol: SymbolID(market: .us, code: $0), name: $0)
        }
        for symbol in symbols.prefix(3) {
            store.add(symbol)
        }

        let customOrder = Array(symbols.prefix(3)).map(\.symbol)
        store.reorder(customOrder)
        store.rememberManualOrder()

        let automaticPresentation = Array(customOrder.reversed())
        store.reorder(automaticPresentation)
        store.add(symbols[3])

        #expect(store.items.map(\.symbol) == [symbols[3].symbol] + automaticPresentation)
        #expect(store.selectedGroup?.manualOrder == [symbols[3].symbol] + customOrder)
        #expect(store.restoreManualOrder())
        #expect(store.items.map(\.symbol) == [symbols[3].symbol] + customOrder)
    }

    @MainActor
    @Test("Adding an existing instrument to another group leads its unpinned section")
    func membershipAdditionLeadsUnpinnedSection() throws {
        let suiteName = "WatchlistNewMembershipOrderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let apple = SymbolInfo(symbol: SymbolID(market: .us, code: "AAPL"), name: "Apple")
        let microsoft = SymbolInfo(symbol: SymbolID(market: .us, code: "MSFT"), name: "Microsoft")
        store.add(apple)
        let techGroupID = try #require(store.createGroup(named: "科技"))
        store.add(microsoft)
        store.rememberManualOrder()
        #expect(store.setPinned(microsoft.symbol, pinned: true))

        store.setMembership(apple.symbol, in: techGroupID, included: true)
        #expect(store.items(in: techGroupID).map(\.symbol) == [microsoft.symbol, apple.symbol])
        #expect(store.group(for: techGroupID)?.manualOrder == [microsoft.symbol, apple.symbol])
        #expect(store.isPinned(microsoft.symbol, in: techGroupID))
        #expect(!store.isPinned(apple.symbol, in: techGroupID))
    }

    @MainActor
    @Test("Unpinning restores the symbol's custom-order position")
    func unpinRestoresCustomOrderPosition() throws {
        let suiteName = "WatchlistPinRestoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let symbols = ["AAPL", "MSFT", "TSLA", "ONDS"].map {
            SymbolInfo(symbol: SymbolID(market: .us, code: $0), name: $0)
        }
        for symbol in symbols {
            store.add(symbol)
        }
        let originalOrder = symbols.map(\.symbol)
        let tesla = symbols[2].symbol
        store.reorder(originalOrder)

        store.rememberManualOrder()
        #expect(store.setPinned(tesla, pinned: true))
        _ = store.restoreManualOrder()
        store.reorder([tesla])
        #expect(store.items.map(\.symbol) == [tesla] + originalOrder.filter { $0 != tesla })

        // This mirrors the view's pre-toggle capture while a pin presentation is active.
        store.rememberManualOrder()
        #expect(store.setPinned(tesla, pinned: false))
        #expect(store.restoreManualOrder())
        #expect(store.items.map(\.symbol) == originalOrder)

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        #expect(reloaded.items.map(\.symbol) == originalOrder)
        #expect(!reloaded.isPinned(tesla))
    }

    @MainActor
    @Test("Multiple pins keep their restore positions while custom order changes")
    func multiplePinsPreserveRestorePositionsDuringDrag() throws {
        let suiteName = "WatchlistMultiPinRestoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let symbols = ["AAPL", "MSFT", "TSLA", "ONDS"].map {
            SymbolInfo(symbol: SymbolID(market: .us, code: $0), name: $0)
        }
        for symbol in symbols {
            store.add(symbol)
        }
        store.reorder(symbols.map(\.symbol))
        let apple = symbols[0].symbol
        let microsoft = symbols[1].symbol
        let tesla = symbols[2].symbol
        let ondas = symbols[3].symbol

        func restorePinnedPresentation() {
            _ = store.restoreManualOrder()
            store.reorder(store.selectedGroup?.pinnedSymbols ?? [])
        }

        store.rememberManualOrder()
        #expect(store.setPinned(microsoft, pinned: true))
        restorePinnedPresentation()
        store.rememberManualOrder()
        #expect(store.setPinned(ondas, pinned: true))
        restorePinnedPresentation()
        #expect(store.items.map(\.symbol) == [ondas, microsoft, apple, tesla])

        // Simulate dragging TSLA ahead of AAPL in the unpinned section.
        store.reorder([ondas, microsoft, tesla, apple])
        store.rememberManualOrder()
        restorePinnedPresentation()
        #expect(store.items.map(\.symbol) == [ondas, microsoft, tesla, apple])

        store.rememberManualOrder()
        #expect(store.setPinned(ondas, pinned: false))
        restorePinnedPresentation()
        #expect(store.items.map(\.symbol) == [microsoft, tesla, apple, ondas])

        store.rememberManualOrder()
        #expect(store.setPinned(microsoft, pinned: false))
        _ = store.restoreManualOrder()
        #expect(store.items.map(\.symbol) == [tesla, microsoft, apple, ondas])
    }

    @MainActor
    @Test("Manual drops preserve the native result and switch pin membership across its boundary")
    func manualDropAtomicallyCrossesPinnedBoundary() throws {
        let suiteName = "WatchlistAtomicMoveTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let symbols = ["AAPL", "MSFT", "TSLA", "ONDS"].map {
            SymbolInfo(symbol: SymbolID(market: .us, code: $0), name: $0)
        }
        for symbol in symbols {
            store.add(symbol)
        }
        store.reorder(symbols.map(\.symbol))
        let apple = symbols[0].symbol
        let microsoft = symbols[1].symbol
        let tesla = symbols[2].symbol
        let ondas = symbols[3].symbol

        store.rememberManualOrder()
        #expect(store.setPinned(microsoft, pinned: true))
        _ = store.restoreManualOrder()
        store.reorder([microsoft])

        // Dropping an unpinned row inside the pinned section pins it at that exact location.
        #expect(store.commitManualMove(
            orderedSymbols: [tesla, microsoft, apple, ondas],
            movingSymbols: [tesla]
        ))
        #expect(store.items.map(\.symbol) == [tesla, microsoft, apple, ondas])
        #expect(store.selectedGroup?.pinnedSymbols == [tesla, microsoft])

        // Dragging the same row below the pinned boundary unpins it without a second reorder.
        #expect(store.commitManualMove(
            orderedSymbols: [microsoft, apple, ondas, tesla],
            movingSymbols: [tesla]
        ))
        #expect(store.items.map(\.symbol) == [microsoft, apple, ondas, tesla])
        #expect(store.selectedGroup?.pinnedSymbols == [microsoft])

        // The boundary itself belongs to the regular section, so this remains unpinned.
        #expect(store.commitManualMove(
            orderedSymbols: [microsoft, ondas, apple, tesla],
            movingSymbols: [ondas]
        ))
        #expect(store.items.map(\.symbol) == [microsoft, ondas, apple, tesla])
        #expect(store.selectedGroup?.pinnedSymbols == [microsoft])

        // Moving above the boundary opts into pinning and keeps the native final order.
        #expect(store.commitManualMove(
            orderedSymbols: [ondas, microsoft, apple, tesla],
            movingSymbols: [ondas]
        ))
        #expect(store.items.map(\.symbol) == [ondas, microsoft, apple, tesla])
        #expect(store.selectedGroup?.pinnedSymbols == [ondas, microsoft])
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
    @Test("Removing from the selected list updates membership and persists")
    func removeFromSelectedGroup() throws {
        let suiteName = "WatchlistGroupRemovalTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let defaultGroupID = try #require(store.selectedGroupID)
        let apple = SymbolInfo(symbol: SymbolID(market: .us, code: "AAPL"), name: "Apple")
        store.add(apple)
        let techGroupID = try #require(store.createGroup(named: "科技"))
        store.add(apple)

        store.remove(apple.symbol)

        #expect(store.selectedGroupID == techGroupID)
        #expect(!store.contains(apple.symbol, in: techGroupID))
        #expect(store.contains(apple.symbol, in: defaultGroupID))
        #expect(store.items.isEmpty)
        #expect(store.item(for: apple.symbol) != nil)

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        #expect(!reloaded.contains(apple.symbol, in: techGroupID))
        #expect(reloaded.contains(apple.symbol, in: defaultGroupID))
        #expect(reloaded.item(for: apple.symbol) != nil)
    }

    @MainActor
    @Test("Instrument type persists and only indices reject positions")
    func instrumentTypeControlsPositions() throws {
        let suiteName = "WatchlistInstrumentTypeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        let index = SymbolInfo(
            symbol: SymbolID(market: .us, code: "^EXAMPLE"),
            name: "Example Index",
            type: .index
        )
        let etf = SymbolInfo(
            symbol: SymbolID(market: .us, code: "SPY"),
            name: "SPDR S&P 500 ETF Trust",
            type: .etf
        )
        store.add(index)
        store.add(etf)

        let indexItem = try #require(store.item(for: index.symbol))
        #expect(indexItem.instrumentType == .index)
        #expect(indexItem.supportsPosition == false)
        store.updateLots(index.symbol, lots: [CostLot(price: 100, quantity: 2)])
        #expect(store.item(for: index.symbol)?.lots.isEmpty == true)

        let etfLot = CostLot(price: 600, quantity: 4)
        #expect(store.item(for: etf.symbol)?.instrumentType == .etf)
        #expect(store.item(for: etf.symbol)?.supportsPosition == true)
        store.updateLots(etf.symbol, lots: [etfLot])
        #expect(store.item(for: etf.symbol)?.lots == [etfLot])

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "自选")
        #expect(reloaded.item(for: index.symbol)?.instrumentType == .index)
        #expect(reloaded.item(for: index.symbol)?.supportsPosition == false)
        #expect(reloaded.item(for: etf.symbol)?.instrumentType == .etf)
        #expect(reloaded.item(for: etf.symbol)?.lots == [etfLot])
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
