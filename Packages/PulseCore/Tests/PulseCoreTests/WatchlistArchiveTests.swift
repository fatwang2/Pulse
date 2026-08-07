import Foundation
import Testing
@testable import PulseCore

@Suite("Watchlist import and export")
struct WatchlistArchiveTests {
    @MainActor
    private func makeStore(
        _ label: String
    ) throws -> (store: WatchlistStore, defaults: UserDefaults, suite: String) {
        let suiteName = "WatchlistArchiveTests.\(label).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (WatchlistStore(defaults: defaults, defaultGroupName: "Watchlist"), defaults, suiteName)
    }

    @MainActor
    @Test("An exported archive restores lists, order, pins, and positions")
    func roundTripRestoresVisibleState() throws {
        let (source, sourceDefaults, sourceSuite) = try makeStore("source")
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }

        let nvda = SymbolID(market: .us, code: "NVDA")
        let tencent = SymbolID(market: .hk, code: "700")
        let btc = SymbolID(market: .crypto, code: "BTC/USDT")

        source.add(SymbolInfo(symbol: nvda, name: "NVIDIA Corp."))
        source.add(SymbolInfo(symbol: tencent, name: "腾讯控股"))
        let cryptoGroup = try #require(source.createGroup(named: "Crypto"))
        source.add(SymbolInfo(symbol: btc, name: "Bitcoin", type: .crypto), to: cryptoGroup)
        source.addTransaction(nvda, PositionTransaction(
            kind: .buy, price: 100, quantity: 3, date: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let firstGroup = try #require(source.group(for: nil)?.id ?? source.selectedGroup?.id)
        _ = source.setPinned(tencent, in: firstGroup, pinned: true)

        let archive = source.archive(exportedAt: Date(timeIntervalSince1970: 0), app: "Pulse test")
        let text = try archive.encoded()

        let (restored, restoredDefaults, restoredSuite) = try makeStore("restored")
        defer { restoredDefaults.removePersistentDomain(forName: restoredSuite) }
        let report = restored.merge(try WatchlistArchive.decoded(from: text))

        #expect(report.symbolsAdded == 3)
        #expect(report.positionsRestored == 1)

        let watchlistGroup = try #require(restored.groups.first { $0.name == "Watchlist" })
        #expect(watchlistGroup.symbols.contains(nvda))
        #expect(watchlistGroup.symbols.contains(tencent))
        #expect(watchlistGroup.pinnedSymbols.contains(tencent))

        let crypto = try #require(restored.groups.first { $0.name == "Crypto" })
        #expect(crypto.symbols == [btc])

        #expect(restored.item(for: nvda)?.displayName == "NVIDIA Corp.")
        #expect(restored.item(for: nvda)?.transactions.count == 1)
        #expect(restored.item(for: btc)?.symbol.cryptoPair?.baseAsset == "BTC")
    }

    @MainActor
    @Test("Exported list order survives the round trip")
    func orderIsPreserved() throws {
        let (source, sourceDefaults, sourceSuite) = try makeStore("order-source")
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }

        let codes = ["AAPL", "MSFT", "TSLA", "AMZN"]
        for code in codes {
            source.add(SymbolInfo(symbol: SymbolID(market: .us, code: code), name: code))
        }
        let exportedOrder = try #require(source.groups.first).symbols
        let text = try source.archive().encoded()

        let (restored, restoredDefaults, restoredSuite) = try makeStore("order-restored")
        defer { restoredDefaults.removePersistentDomain(forName: restoredSuite) }
        restored.merge(try WatchlistArchive.decoded(from: text))

        #expect(try #require(restored.groups.first).symbols == exportedOrder)
    }

    @MainActor
    @Test("A hand-written archive needs only a market and a code")
    func minimalEntriesImport() throws {
        let (store, defaults, suite) = try makeStore("minimal")
        defer { defaults.removePersistentDomain(forName: suite) }

        let text = """
        {
          "format": "pulse.watchlist",
          "version": 1,
          "lists": [
            { "name": "Core", "entries": [
                { "market": "us", "code": "NVDA" },
                { "market": "hk", "code": "700" },
                { "market": "crypto", "code": "BTC/USDT" },
                { "market": "us", "code": "SPX" }
            ] }
          ]
        }
        """

        let report = store.merge(try WatchlistArchive.decoded(from: text))
        #expect(report.listsCreated == 1)
        #expect(report.symbolsAdded == 4)

        let core = try #require(store.groups.first { $0.name == "Core" })
        #expect(core.symbols.count == 4)

        // A code-only entry parks the code as the display name with no provenance,
        // which is the state the quote refresh upgrades to a real name.
        let nvda = try #require(store.item(for: SymbolID(market: .us, code: "NVDA")))
        #expect(nvda.displayName == "NVDA")
        #expect(nvda.displayNameSource == nil)

        // Structured identities still resolve from their plain text form.
        #expect(store.item(for: SymbolID(market: .crypto, code: "BTC/USDT")) != nil)
        let index = try #require(store.item(for: SymbolID(market: .us, code: "SPX")))
        #expect(index.symbol.indexID == .sp500)
    }

    @MainActor
    @Test("Importing is additive and never overwrites existing work")
    func importOnlyAdds() throws {
        let (store, defaults, suite) = try makeStore("additive")
        defer { defaults.removePersistentDomain(forName: suite) }

        let nvda = SymbolID(market: .us, code: "NVDA")
        store.add(SymbolInfo(symbol: nvda, name: "英伟达"))
        store.addTransaction(nvda, PositionTransaction(
            kind: .buy, price: 50, quantity: 2, date: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let text = """
        {
          "format": "pulse.watchlist",
          "version": 1,
          "lists": [
            { "name": "Watchlist", "entries": [
                { "market": "us", "code": "NVDA", "name": "NVIDIA Corp.",
                  "transactions": [
                    { "id": "\(UUID().uuidString)", "kind": "buy", "price": 999, "quantity": 99,
                      "date": "2020-01-01T00:00:00Z", "createdAt": "2020-01-01T00:00:00Z" }
                  ] }
            ] }
          ]
        }
        """

        let report = store.merge(try WatchlistArchive.decoded(from: text))
        #expect(report.symbolsAdded == 0)
        #expect(report.symbolsAlreadyPresent == 1)
        #expect(report.positionsRestored == 0)
        #expect(!report.changedAnything)

        // The saved name and the live ledger both win over the archive.
        #expect(store.item(for: nvda)?.displayName == "英伟达")
        #expect(store.item(for: nvda)?.transactions.count == 1)
        #expect(store.item(for: nvda)?.transactions.first?.price == 50)
    }

    @MainActor
    @Test("Re-importing the same archive changes nothing")
    func repeatedImportIsIdempotent() throws {
        let (store, defaults, suite) = try makeStore("idempotent")
        defer { defaults.removePersistentDomain(forName: suite) }

        store.add(SymbolInfo(symbol: SymbolID(market: .us, code: "AAPL"), name: "Apple Inc."))
        _ = store.createGroup(named: "Crypto")
        let text = try store.archive().encoded()

        let first = store.merge(try WatchlistArchive.decoded(from: text))
        #expect(!first.changedAnything)

        let groupsBefore = store.groups
        let itemsBefore = store.items
        store.merge(try WatchlistArchive.decoded(from: text))
        #expect(store.groups == groupsBefore)
        #expect(store.items == itemsBefore)
    }

    @MainActor
    @Test("An empty position adopts the archived trades")
    func archivedPositionFillsAnEmptyLedger() throws {
        let (store, defaults, suite) = try makeStore("position")
        defer { defaults.removePersistentDomain(forName: suite) }

        let nvda = SymbolID(market: .us, code: "NVDA")
        store.add(SymbolInfo(symbol: nvda, name: "NVIDIA Corp."))

        let text = """
        {
          "format": "pulse.watchlist",
          "version": 1,
          "lists": [
            { "name": "Watchlist", "entries": [
                { "market": "us", "code": "NVDA",
                  "transactions": [
                    { "id": "\(UUID().uuidString)", "kind": "buy", "price": 120, "quantity": 4,
                      "date": "2026-01-05T00:00:00Z", "createdAt": "2026-01-05T00:00:00Z" }
                  ] }
            ] }
          ]
        }
        """

        let report = store.merge(try WatchlistArchive.decoded(from: text))
        #expect(report.positionsRestored == 1)
        #expect(report.changedAnything)

        let item = try #require(store.item(for: nvda))
        #expect(item.transactions.count == 1)
        // The derived single-lot cache older consumers read is rebuilt too.
        #expect(item.lots.first?.quantity == 4)
        #expect(item.lots.first?.price == 120)
    }

    @Test("Payloads that are not a Pulse archive are rejected with a reason")
    func decodingRejectsForeignPayloads() throws {
        #expect(throws: WatchlistArchive.DecodingFailure.notJSON) {
            try WatchlistArchive.decoded(from: "   ")
        }
        #expect(throws: WatchlistArchive.DecodingFailure.notJSON) {
            try WatchlistArchive.decoded(from: "NVDA, AAPL, 700")
        }
        #expect(throws: WatchlistArchive.DecodingFailure.wrongFormat("shortcuts.list")) {
            try WatchlistArchive.decoded(
                from: #"{"format":"shortcuts.list","version":1,"lists":[]}"#
            )
        }
        #expect(throws: WatchlistArchive.DecodingFailure.unsupportedVersion(99)) {
            try WatchlistArchive.decoded(
                from: #"{"format":"pulse.watchlist","version":99,"lists":[{"name":"A","entries":[]}]}"#
            )
        }
        #expect(throws: WatchlistArchive.DecodingFailure.noLists) {
            try WatchlistArchive.decoded(
                from: #"{"format":"pulse.watchlist","version":1,"lists":[]}"#
            )
        }
    }

    @Test("The exported document is readable and self-describing")
    func exportedDocumentIsHumanReadable() throws {
        let archive = WatchlistArchive(
            exportedAt: Date(timeIntervalSince1970: 1_767_225_600),
            app: "Pulse 0.11.0",
            lists: [.init(name: "Core", entries: [
                .init(market: .us, code: "NVDA", name: "NVIDIA Corp.", type: .equity)
            ])]
        )
        let text = try archive.encoded()

        #expect(text.contains("\"format\" : \"pulse.watchlist\""))
        // ISO-8601 rather than the reference-date doubles the app stores internally.
        #expect(text.contains("2026-01-01T"))
        #expect(text.contains("\"code\" : \"NVDA\""))

        let reparsed = try WatchlistArchive.decoded(from: text)
        #expect(reparsed == archive)
    }
}
