import Foundation
import Testing
@testable import PulseCore

@Suite("Position ledger replay")
struct PositionLedgerTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_750_000_000 + TimeInterval(offset) * 86_400)
    }

    @Test("Buys blend into a moving weighted average cost")
    func buysBlendAverageCost() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .buy, price: 100, quantity: 10, date: day(0)),
            PositionTransaction(kind: .buy, price: 200, quantity: 10, date: day(1)),
        ])
        #expect(ledger.quantity == 20)
        #expect(ledger.averageCost == 150)
        #expect(ledger.costBasis == 3_000)
        #expect(ledger.realizedPnL == 0)
    }

    @Test("A sell realizes (price − average cost) × quantity and keeps the remaining units' cost")
    func sellRealizesAgainstAverageCost() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .buy, price: 100, quantity: 20, date: day(0)),
            PositionTransaction(kind: .sell, price: 130, quantity: 5, date: day(1)),
        ])
        #expect(ledger.quantity == 15)
        #expect(ledger.averageCost == 100)
        #expect(ledger.realizedPnL == 150)
        #expect(ledger.entries.last?.realizedPnL == 150)
    }

    @Test("Selling out flattens the position but realized P&L survives")
    func sellingOutKeepsRealizedPnL() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .buy, price: 100, quantity: 10, date: day(0)),
            PositionTransaction(kind: .sell, price: 90, quantity: 10, date: day(1)),
        ])
        #expect(ledger.quantity == 0)
        #expect(!ledger.hasOpenPosition)
        #expect(ledger.realizedPnL == -100)
    }

    @Test("An adjustment overwrites quantity and cost without realizing P&L")
    func adjustmentOverwrites() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .buy, price: 100, quantity: 10, date: day(0)),
            PositionTransaction(kind: .sell, price: 120, quantity: 5, date: day(1)),
            PositionTransaction(kind: .adjustment, price: 185, quantity: 110, date: day(2)),
        ])
        #expect(ledger.quantity == 110)
        #expect(ledger.averageCost == 185)
        // The pre-adjustment sell keeps its realized P&L; the adjustment adds none.
        #expect(ledger.realizedPnL == 100)
    }

    @Test("A sell past the holding closes the long, then flips short at the trade price")
    func sellPastFlatFlipsShort() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .buy, price: 100, quantity: 5, date: day(0)),
            PositionTransaction(kind: .sell, price: 120, quantity: 50, date: day(1)),
        ])
        // 5 close at +20 each; the remaining 45 open a short at 120.
        #expect(ledger.quantity == -45)
        #expect(ledger.averageCost == 120)
        #expect(ledger.realizedPnL == 100)
        #expect(ledger.hasOpenPosition)
    }

    @Test("Selling first opens a short whose average blends the entry prices")
    func sellFirstOpensShort() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .sell, price: 100, quantity: 10, date: day(0)),
            PositionTransaction(kind: .sell, price: 200, quantity: 10, date: day(1)),
        ])
        #expect(ledger.quantity == -20)
        #expect(ledger.averageCost == 150)
        #expect(ledger.costBasis == -3_000)
        #expect(ledger.realizedPnL == 0)
        #expect(ledger.hasOpenPosition)
    }

    @Test("A buy covers a short, realizing (average short price − price) × covered")
    func buyCoversShort() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .sell, price: 150, quantity: 10, date: day(0)),
            PositionTransaction(kind: .buy, price: 100, quantity: 4, date: day(1)),
        ])
        #expect(ledger.quantity == -6)
        #expect(ledger.averageCost == 150)
        #expect(ledger.realizedPnL == 200)
        #expect(ledger.entries.last?.realizedPnL == 200)
    }

    @Test("Covering the whole short flattens it; realized P&L survives")
    func coveringOutKeepsRealizedPnL() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .sell, price: 150, quantity: 10, date: day(0)),
            PositionTransaction(kind: .buy, price: 170, quantity: 10, date: day(1)),
        ])
        #expect(ledger.quantity == 0)
        #expect(!ledger.hasOpenPosition)
        #expect(ledger.averageCost == 0)
        #expect(ledger.realizedPnL == -200)
    }

    @Test("A buy past the short covers it, then flips long at the trade price")
    func buyPastFlatFlipsLong() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .sell, price: 150, quantity: 5, date: day(0)),
            PositionTransaction(kind: .buy, price: 100, quantity: 8, date: day(1)),
        ])
        #expect(ledger.quantity == 3)
        #expect(ledger.averageCost == 100)
        #expect(ledger.realizedPnL == 250)
    }

    @Test("A negative-quantity adjustment calibrates a short without realizing P&L")
    func adjustmentCalibratesShort() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .adjustment, price: 90, quantity: -12, date: day(0)),
        ])
        #expect(ledger.quantity == -12)
        #expect(ledger.averageCost == 90)
        #expect(ledger.realizedPnL == 0)
        #expect(ledger.hasOpenPosition)
    }

    @Test("Short position metrics profit when the price falls")
    func shortPositionMetrics() throws {
        var item = WatchItem(
            symbol: SymbolID(market: .us, code: "AAPL"),
            displayName: "Apple"
        )
        item.transactions = [
            PositionTransaction(kind: .sell, price: 150, quantity: 10, date: day(0)),
        ]
        #expect(item.hasPosition)
        #expect(item.isShortPosition)
        #expect(item.positionQuantity == -10)
        #expect(item.averageCost == 150)

        let quote = Quote(
            symbol: item.symbol,
            price: 120,
            previousClose: 130,
            timestamp: day(1)
        )
        let metrics = try #require(PositionMetrics(item: item, quote: quote))
        #expect(metrics.marketValue == -1_200)
        #expect(metrics.costBasis == -1_500)
        // Shorted at 150, now 120 → +30 per unit.
        #expect(metrics.totalPnL == 300)
        #expect(metrics.totalReturnPercent == 20)
        // Price fell 10 today → a short gains 100 and the percent agrees in sign.
        #expect(metrics.todayPnL == 100)
        #expect(metrics.todayReturnPercent > 0)
    }

    @Test("Replay sorts by trade date, breaking same-day ties by insertion time")
    func replayOrder() {
        let backdatedBuy = PositionTransaction(
            kind: .buy, price: 100, quantity: 10, date: day(0), createdAt: day(9)
        )
        let sell = PositionTransaction(
            kind: .sell, price: 150, quantity: 10, date: day(5), createdAt: day(5)
        )
        // Entered sell-first; the backdated buy must still replay before it.
        let ledger = PositionLedger(transactions: [sell, backdatedBuy])
        #expect(ledger.quantity == 0)
        #expect(ledger.realizedPnL == 500)

        let sameDayFirst = PositionTransaction(
            kind: .buy, price: 100, quantity: 1, date: day(0), createdAt: day(1)
        )
        let sameDaySecond = PositionTransaction(
            kind: .buy, price: 200, quantity: 1, date: day(0), createdAt: day(2)
        )
        let ordered = PositionLedger.replayOrdered([sameDaySecond, sameDayFirst])
        #expect(ordered.map(\.id) == [sameDayFirst.id, sameDaySecond.id])
    }

    @Test("WatchItem prefers the ledger over legacy lots once transactions exist")
    func watchItemPrefersLedger() {
        var item = WatchItem(
            symbol: SymbolID(market: .us, code: "AAPL"),
            displayName: "Apple",
            lots: [CostLot(price: 999, quantity: 999)]
        )
        item.transactions = [
            PositionTransaction(kind: .buy, price: 100, quantity: 10, date: day(0)),
        ]
        #expect(item.positionQuantity == 10)
        #expect(item.averageCost == 100)
        #expect(item.hasPosition)
        #expect(item.hasPositionHistory)
    }

    @Test("Legacy lots materialize as one opening adjustment at their combined average cost")
    func materializeLegacyLots() {
        let firstDate = day(0)
        let item = WatchItem(
            symbol: SymbolID(market: .us, code: "AAPL"),
            displayName: "Apple",
            lots: [
                CostLot(price: 100, quantity: 10, date: day(3)),
                CostLot(price: 200, quantity: 10, date: firstDate),
            ]
        )
        let materialized = item.materializedTransactions()
        #expect(materialized.count == 1)
        #expect(materialized.first?.kind == .adjustment)
        #expect(materialized.first?.quantity == 20)
        #expect(materialized.first?.price == 150)
        #expect(materialized.first?.date == firstDate)
    }

    @Test("Watch items saved before the transaction upgrade still decode")
    func decodesLegacyWatchItemJSON() throws {
        let json = """
        {
            "symbol": {"market": "us", "code": "AAPL"},
            "displayName": "Apple",
            "addedAt": 700000000,
            "lots": [{"id": "\(UUID().uuidString)", "price": 187.2, "quantity": 120}]
        }
        """
        let item = try JSONDecoder().decode(WatchItem.self, from: Data(json.utf8))
        #expect(item.transactions.isEmpty)
        #expect(item.positionQuantity == 120)
        #expect(item.averageCost == 187.2)
    }

    /// Two trades entered back to back share both timestamps roughly three times
    /// in four, so this is the ordinary case rather than an edge one. Replay must
    /// fall back to the order they are stored in — the order the user entered
    /// them — and not to anything derived from `id`, which is a random UUID.
    @Test("Trades with identical timestamps replay in the order they were stored")
    func identicalTimestampsKeepStoredOrder() throws {
        let stamp = Date(timeIntervalSince1970: 1_787_000_000)
        let buy = PositionTransaction(
            kind: .buy, price: 100, quantity: 10, date: stamp, createdAt: stamp)
        let sell = PositionTransaction(
            kind: .sell, price: 130, quantity: 4, date: stamp, createdAt: stamp)

        #expect(PositionLedger.replayOrdered([buy, sell]).map(\.id) == [buy.id, sell.id])
        // The reverse array is a different ledger, not the same one re-sorted.
        #expect(PositionLedger.replayOrdered([sell, buy]).map(\.id) == [sell.id, buy.id])

        // Sorting is idempotent: replaying an already-ordered list cannot reshuffle it.
        let once = PositionLedger.replayOrdered([buy, sell])
        #expect(PositionLedger.replayOrdered(once).map(\.id) == once.map(\.id))
    }

    /// A real timestamp difference still outranks stored order, so an entry
    /// back-dated to an earlier day replays first however it was appended.
    @Test("An earlier trade date still wins over stored order")
    func earlierDateWinsOverStoredOrder() throws {
        let older = PositionTransaction(
            kind: .buy, price: 100, quantity: 10,
            date: Date(timeIntervalSince1970: 1_786_000_000),
            createdAt: Date(timeIntervalSince1970: 1_787_000_000))
        let newer = PositionTransaction(
            kind: .sell, price: 130, quantity: 4,
            date: Date(timeIntervalSince1970: 1_787_000_000),
            createdAt: Date(timeIntervalSince1970: 1_787_000_000))

        #expect(PositionLedger.replayOrdered([newer, older]).map(\.id) == [older.id, newer.id])
    }

    /// The entry form dates trades at local midnight while a quick-set
    /// calibration keeps the time it was made, so two same-day entries rarely
    /// share an instant. Ordering by instant replayed the midnight-dated buy
    /// ahead of a calibration made that morning, and the calibration wiped it.
    @Test("Same-day entries order by insertion time, whatever time of day they carry")
    func sameDayEntriesIgnoreTimeOfDay() throws {
        let calendar = Calendar.current
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2)))
        let morning = try #require(calendar.date(byAdding: .hour, value: 9, to: day))
        let noon = try #require(calendar.date(byAdding: .hour, value: 12, to: day))
        let calibration = PositionTransaction(
            kind: .adjustment, price: 150, quantity: 100, date: morning, createdAt: morning)
        let buy = PositionTransaction(
            kind: .buy, price: 200, quantity: 10, date: day, createdAt: noon)

        let ledger = PositionLedger(transactions: [buy, calibration])
        #expect(ledger.entries.map(\.id) == [calibration.id, buy.id])
        #expect(ledger.quantity == 110)
    }

}

@Suite("Watchlist store transactions")
struct WatchlistStoreTransactionTests {
    @MainActor
    private func makeStore() throws -> (WatchlistStore, UserDefaults, String) {
        let suiteName = "WatchlistStoreTransactionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (WatchlistStore(defaults: defaults, defaultGroupName: "Watchlist"), defaults, suiteName)
    }

    private let apple = SymbolInfo(
        symbol: SymbolID(market: .us, code: "AAPL"),
        name: "Apple",
        type: .equity
    )

    @MainActor
    @Test("The first trade folds legacy lots into the ledger and refreshes the lot cache")
    func firstTradeFoldsLegacyLots() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.add(apple)
        store.updateLots(apple.symbol, lots: [CostLot(price: 100, quantity: 10)])
        store.addTransaction(apple.symbol, PositionTransaction(kind: .buy, price: 200, quantity: 10))

        let item = try #require(store.item(for: apple.symbol))
        #expect(item.transactions.count == 2)
        #expect(item.transactions.first?.kind == .adjustment)
        #expect(item.positionQuantity == 20)
        #expect(item.averageCost == 150)
        // Derived single-lot cache mirrors the open position for lot-based consumers.
        #expect(item.lots.count == 1)
        #expect(item.lots.first?.quantity == 20)
        #expect(item.lots.first?.price == 150)
    }

    @MainActor
    @Test("A trade dated today lands on top of a quick-set made earlier that day")
    func sameDayTradeFollowsEarlierCalibration() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.add(apple)
        // Quick-set carries the current time; the entry form then dates the
        // buy at local midnight, exactly as the Mac popover does.
        store.calibratePosition(apple.symbol, quantity: 100, averageCost: 150)
        store.addTransaction(apple.symbol, PositionTransaction(
            kind: .buy, price: 200, quantity: 10, date: Calendar.current.startOfDay(for: .now)
        ))

        let item = try #require(store.item(for: apple.symbol))
        #expect(item.transactions.map(\.kind) == [.adjustment, .buy])
        #expect(item.positionQuantity == 110)
    }

    @MainActor
    @Test("Deleting a transaction replays the remainder")
    func deleteReplays() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.add(apple)
        let buy = PositionTransaction(kind: .buy, price: 100, quantity: 10)
        let sell = PositionTransaction(kind: .sell, price: 150, quantity: 10)
        store.addTransaction(apple.symbol, buy)
        store.addTransaction(apple.symbol, sell)
        #expect(store.item(for: apple.symbol)?.realizedPnL == 500)

        store.deleteTransaction(apple.symbol, id: sell.id)
        let item = try #require(store.item(for: apple.symbol))
        #expect(item.realizedPnL == 0)
        #expect(item.positionQuantity == 10)
        #expect(item.lots.first?.quantity == 10)
    }

    @MainActor
    @Test("Clearing a position with history keeps the trade log and realized P&L")
    func clearKeepsHistory() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.add(apple)
        store.addTransaction(apple.symbol, PositionTransaction(kind: .buy, price: 100, quantity: 10))
        store.addTransaction(apple.symbol, PositionTransaction(kind: .sell, price: 150, quantity: 5))
        store.clearPosition(apple.symbol)

        let item = try #require(store.item(for: apple.symbol))
        #expect(!item.hasPosition)
        #expect(item.lots.isEmpty)
        #expect(item.transactions.count == 3)
        #expect(item.realizedPnL == 250)
        #expect(item.hasPositionHistory)
    }

    @MainActor
    @Test("Calibration overwrites the position as one adjustment")
    func calibrationOverwrites() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.add(apple)
        store.addTransaction(apple.symbol, PositionTransaction(kind: .buy, price: 100, quantity: 10))
        store.calibratePosition(apple.symbol, quantity: 120, averageCost: 187.2)

        let item = try #require(store.item(for: apple.symbol))
        #expect(item.positionQuantity == 120)
        #expect(item.averageCost == 187.2)
        #expect(item.realizedPnL == 0)
        #expect(item.lots.first?.quantity == 120)
    }

    @MainActor
    @Test("Transactions persist across a reload")
    func transactionsPersist() throws {
        let suiteName = "WatchlistStoreTransactionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "Watchlist")
        store.add(apple)
        store.addTransaction(apple.symbol, PositionTransaction(kind: .buy, price: 100, quantity: 10))
        store.addTransaction(apple.symbol, PositionTransaction(kind: .sell, price: 130, quantity: 4))

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "Watchlist")
        let item = try #require(reloaded.item(for: apple.symbol))
        #expect(item.transactions.count == 2)
        #expect(item.positionQuantity == 6)
        #expect(item.realizedPnL == 120)
    }

    @MainActor
    @Test("Removing and later re-adding a symbol restores its persisted trade history")
    func removedSymbolRestoresTransactions() throws {
        let suiteName = "WatchlistStoreTransactionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchlistStore(defaults: defaults, defaultGroupName: "Watchlist")
        store.add(apple)
        let buy = PositionTransaction(kind: .buy, price: 100, quantity: 10)
        let sell = PositionTransaction(kind: .sell, price: 130, quantity: 4)
        store.addTransaction(apple.symbol, buy)
        store.addTransaction(apple.symbol, sell)

        store.remove(apple.symbol)

        #expect(store.item(for: apple.symbol) == nil)
        #expect(store.symbols.isEmpty)
        #expect(store.isEmpty)

        let reloaded = WatchlistStore(defaults: defaults, defaultGroupName: "Watchlist")
        #expect(reloaded.item(for: apple.symbol) == nil)
        #expect(reloaded.symbols.isEmpty)

        reloaded.add(apple)

        let restored = try #require(reloaded.item(for: apple.symbol))
        #expect(restored.transactions.map(\.id) == [buy.id, sell.id])
        #expect(restored.positionQuantity == 6)
        #expect(restored.realizedPnL == 120)

        let reloadedAgain = WatchlistStore(defaults: defaults, defaultGroupName: "Watchlist")
        #expect(reloadedAgain.item(for: apple.symbol)?.transactions.map(\.id) == [buy.id, sell.id])
    }

    @MainActor
    @Test("Sell-first then buy records a short round trip through the store")
    func shortRoundTrip() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.add(apple)
        store.addTransaction(apple.symbol, PositionTransaction(kind: .sell, price: 150, quantity: 10))
        var item = try #require(store.item(for: apple.symbol))
        #expect(item.positionQuantity == -10)
        #expect(item.averageCost == 150)
        #expect(item.isShortPosition)
        // Lot cache mirrors the short as a negative lot; old builds treat it as no position.
        #expect(item.lots.first?.quantity == -10)

        store.addTransaction(apple.symbol, PositionTransaction(kind: .buy, price: 100, quantity: 10))
        item = try #require(store.item(for: apple.symbol))
        #expect(item.positionQuantity == 0)
        #expect(!item.hasPosition)
        #expect(item.realizedPnL == 500)
        #expect(item.lots.isEmpty)
    }

    @MainActor
    @Test("Calibrating to a negative quantity sets up a short")
    func calibrationSupportsShort() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.add(apple)
        store.calibratePosition(apple.symbol, quantity: -30, averageCost: 187.2)

        let item = try #require(store.item(for: apple.symbol))
        #expect(item.positionQuantity == -30)
        #expect(item.averageCost == 187.2)
        #expect(item.realizedPnL == 0)
        #expect(item.isShortPosition)
    }

    @MainActor
    @Test("Clearing a short position keeps its history")
    func clearShortKeepsHistory() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.add(apple)
        store.addTransaction(apple.symbol, PositionTransaction(kind: .sell, price: 150, quantity: 10))
        store.addTransaction(apple.symbol, PositionTransaction(kind: .buy, price: 120, quantity: 5))
        store.clearPosition(apple.symbol)

        let item = try #require(store.item(for: apple.symbol))
        #expect(!item.hasPosition)
        #expect(item.realizedPnL == 150)
        #expect(item.transactions.count == 3)
    }

    @MainActor
    @Test("Non-positive price or quantity never reaches the ledger")
    func storeRejectsInvalidEntries() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.add(apple)
        store.addTransaction(apple.symbol, PositionTransaction(kind: .buy, price: 0, quantity: 10))
        store.addTransaction(apple.symbol, PositionTransaction(kind: .buy, price: 100, quantity: 0))
        #expect(store.item(for: apple.symbol)?.transactions.isEmpty == true)
    }
}
