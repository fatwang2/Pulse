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

    @Test("A backdated oversell clamps to what was held at that point")
    func oversellClamps() {
        let ledger = PositionLedger(transactions: [
            PositionTransaction(kind: .buy, price: 100, quantity: 5, date: day(0)),
            PositionTransaction(kind: .sell, price: 120, quantity: 50, date: day(1)),
        ])
        #expect(ledger.quantity == 0)
        #expect(ledger.realizedPnL == 100)
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
