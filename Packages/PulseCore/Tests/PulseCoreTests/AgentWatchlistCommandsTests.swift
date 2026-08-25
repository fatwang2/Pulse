import Foundation
import Testing
@testable import PulseCore

@MainActor
@Suite("Agent watchlist commands")
struct AgentWatchlistCommandsTests {
    private func makeStore() throws -> (WatchlistStore, UserDefaults, String) {
        let suiteName = "AgentWatchlistCommandsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (
            WatchlistStore(defaults: defaults, defaultGroupName: "Watchlist"),
            defaults,
            suiteName
        )
    }

    @Test
    func addRequiresGroupAndDoesNotUseSelection() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selectedID = try #require(store.selectedGroupID)
        let techID = try #require(store.createGroup(named: "Tech"))
        store.selectGroup(selectedID)
        let commands = AgentWatchlistCommands(store: store)

        let mutation = try commands.addSymbol(
            AgentSymbolRef(market: "us", code: "NVDA"),
            name: "NVIDIA",
            to: techID
        ).get()

        #expect(store.selectedGroupID == selectedID)
        #expect(store.contains(SymbolID(market: .us, code: "NVDA"), in: techID))
        #expect(!store.contains(SymbolID(market: .us, code: "NVDA"), in: selectedID))
        #expect(mutation.didChangeSymbolUnion)
        #expect(!mutation.alreadyApplied)
    }

    @Test
    func removeFromNonSelectedGroupWorks() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selectedID = try #require(store.selectedGroupID)
        let techID = try #require(store.createGroup(named: "Tech"))
        let commands = AgentWatchlistCommands(store: store)
        let ref = AgentSymbolRef(market: "us", code: "NVDA")
        _ = try commands.addSymbol(ref, name: "NVIDIA", to: techID).get()
        store.selectGroup(selectedID)

        let mutation = try commands.removeSymbol(ref, from: techID).get()

        #expect(store.selectedGroupID == selectedID)
        #expect(!store.contains(SymbolID(market: .us, code: "NVDA"), in: techID))
        #expect(mutation.didChangeSymbolUnion)
        #expect(!mutation.alreadyApplied)
    }

    @Test
    func createGroupDoesNotLeaveSelectionOnNewGroup() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selectedID = try #require(store.selectedGroupID)
        let commands = AgentWatchlistCommands(store: store)

        let mutation = try commands.createGroup(named: "Tech").get()

        #expect(store.selectedGroupID == selectedID)
        #expect(mutation.value.name == "Tech")
        #expect(!mutation.didChangeSymbolUnion)
    }

    @Test
    func recordTradeWithSameIDIsIdempotent() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let groupID = try #require(store.selectedGroupID)
        let commands = AgentWatchlistCommands(store: store)
        let ref = AgentSymbolRef(market: "us", code: "NVDA")
        _ = try commands.addSymbol(ref, name: "NVIDIA", to: groupID).get()
        let transactionID = UUID()
        let draft = AgentTradeDraft(
            symbol: ref,
            kind: .buy,
            quantity: 10,
            price: 120,
            date: Date(timeIntervalSince1970: 1_750_000_000),
            id: transactionID
        )

        let first = try commands.recordTrade(draft).get()
        let second = try commands.recordTrade(draft).get()

        #expect(first.value.transactions.map(\.id) == [transactionID])
        #expect(!first.alreadyApplied)
        #expect(second.value.transactions.map(\.id) == [transactionID])
        #expect(second.alreadyApplied)
        #expect(store.item(for: SymbolID(market: .us, code: "NVDA"))?.transactions.count == 1)
    }

    @Test
    func lastGroupDeleteFails() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let groupID = try #require(store.selectedGroupID)
        let commands = AgentWatchlistCommands(store: store)

        switch commands.deleteGroup(groupID) {
        case .failure(.lastGroupProtected):
            break
        default:
            Issue.record("Expected lastGroupProtected")
        }
    }

    @Test
    func indexCannotRecordTrade() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let groupID = try #require(store.selectedGroupID)
        let commands = AgentWatchlistCommands(store: store)
        let ref = AgentSymbolRef(market: "us", code: "^EXAMPLE")
        _ = try commands.addSymbol(ref, name: "Example Index", type: .index, to: groupID).get()
        let draft = AgentTradeDraft(
            symbol: ref,
            kind: .buy,
            quantity: 1,
            price: 100,
            date: .now
        )

        switch commands.recordTrade(draft) {
        case .failure(.positionNotSupported):
            break
        default:
            Issue.record("Expected positionNotSupported")
        }
    }

    @Test
    func reorderGroupsSetsTagBarOrderWithoutChangingSelection() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultID = try #require(store.selectedGroupID)
        let hkID = try #require(store.createGroup(named: "HK"))
        let usID = try #require(store.createGroup(named: "US"))
        store.selectGroup(defaultID)
        let commands = AgentWatchlistCommands(store: store)

        let mutation = try commands.reorderGroups([usID, defaultID, hkID]).get()

        #expect(store.groups.map(\.id) == [usID, defaultID, hkID])
        #expect(store.selectedGroupID == defaultID)
        #expect(mutation.value.groups.map(\.id) == [usID, defaultID, hkID])
        #expect(!mutation.alreadyApplied)
        #expect(!mutation.didChangeSymbolUnion)

        let again = try commands.reorderGroups([usID, defaultID, hkID]).get()
        #expect(again.alreadyApplied)
    }

    @Test
    func reorderSymbolsSetsCustomOrderAndRespectsPins() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let groupID = try #require(store.selectedGroupID)
        let commands = AgentWatchlistCommands(store: store)
        let aapl = AgentSymbolRef(market: "us", code: "AAPL")
        let msft = AgentSymbolRef(market: "us", code: "MSFT")
        let nvda = AgentSymbolRef(market: "us", code: "NVDA")
        _ = try commands.addSymbol(aapl, name: "Apple", to: groupID).get()
        _ = try commands.addSymbol(msft, name: "Microsoft", to: groupID).get()
        _ = try commands.addSymbol(nvda, name: "NVIDIA", to: groupID).get()

        let aaplID = SymbolID(market: .us, code: "AAPL")
        let msftID = SymbolID(market: .us, code: "MSFT")
        let nvdaID = SymbolID(market: .us, code: "NVDA")
        #expect(store.setPinned(msftID, in: groupID, pinned: true))

        // Request puts unpinned before pinned; store coerces to pinned-first.
        let mutation = try commands.reorderSymbols([aapl, nvda, msft], in: groupID).get()

        #expect(store.group(for: groupID)?.symbols == [msftID, aaplID, nvdaID])
        #expect(store.group(for: groupID)?.pinnedSymbols == [msftID])
        #expect(store.group(for: groupID)?.manualOrder != nil)
        #expect(mutation.value.symbols.map(\.code) == ["MSFT", "AAPL", "NVDA"])
        #expect(!mutation.alreadyApplied)
        #expect(store.selectedGroupID == groupID)
    }

    @Test
    func reorderSymbolsRejectsPartialLists() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let groupID = try #require(store.selectedGroupID)
        let commands = AgentWatchlistCommands(store: store)
        let aapl = AgentSymbolRef(market: "us", code: "AAPL")
        let msft = AgentSymbolRef(market: "us", code: "MSFT")
        _ = try commands.addSymbol(aapl, name: "Apple", to: groupID).get()
        _ = try commands.addSymbol(msft, name: "Microsoft", to: groupID).get()

        switch commands.reorderSymbols([aapl], in: groupID) {
        case .failure(.invalidSymbolOrder):
            break
        default:
            Issue.record("Expected invalidSymbolOrder")
        }
    }
}
