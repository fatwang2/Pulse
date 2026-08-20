import Foundation
import Observation

/// Watchlist instruments plus named tag membership, backed by UserDefaults.
/// Instruments and positions are stored once even when they appear in several groups.
/// Trade history for removed instruments is retained separately until the symbol is added again.
@MainActor
@Observable
public final class WatchlistStore {
    public private(set) var allItems: [WatchItem] = []
    public private(set) var groups: [WatchlistGroup] = []
    public private(set) var selectedGroupID: UUID?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "pulse.watchlists.v2"
    @ObservationIgnored private let legacyStorageKey = "pulse.watchlist.v1"
    @ObservationIgnored private let legacyManualOrderKey = "pulse.watchlist.manualOrder.v1"
    @ObservationIgnored private let initialGroupName: String
    @ObservationIgnored private var retainedHistoryItems: [WatchItem] = []

    public init(defaults: UserDefaults = .standard, defaultGroupName: String? = nil) {
        self.defaults = defaults
        self.initialGroupName = defaultGroupName ?? Self.localizedDefaultGroupName
        load()
    }

    /// Items in the selected group, in that group's current presentation order.
    public var items: [WatchItem] {
        guard let group = selectedGroup else { return [] }
        let bySymbol = Dictionary(uniqueKeysWithValues: allItems.map { ($0.symbol, $0) })
        return group.symbols.compactMap { bySymbol[$0] }
    }

    /// Every followed instrument, de-duplicated across groups. Refresh and streaming use this union.
    public var symbols: [SymbolID] { allItems.map(\.symbol) }

    public var isEmpty: Bool { allItems.isEmpty }

    public var selectedGroup: WatchlistGroup? {
        groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    public func items(in groupID: UUID?) -> [WatchItem] {
        guard let group = group(for: groupID) else { return [] }
        let bySymbol = Dictionary(uniqueKeysWithValues: allItems.map { ($0.symbol, $0) })
        return group.symbols.compactMap { bySymbol[$0] }
    }

    public func group(for id: UUID?) -> WatchlistGroup? {
        guard let id else { return groups.first }
        return groups.first { $0.id == id }
    }

    public func selectGroup(_ id: UUID) {
        guard groups.contains(where: { $0.id == id }), selectedGroupID != id else { return }
        selectedGroupID = id
        save()
    }

    /// Reorders a tag relative to another tag while preserving the selected tag and memberships.
    /// Moving right places the source after the destination; moving left places it before.
    public func moveGroup(_ sourceID: UUID, relativeTo destinationID: UUID) {
        guard sourceID != destinationID,
              let sourceIndex = groups.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = groups.firstIndex(where: { $0.id == destinationID }) else { return }

        let moving = groups.remove(at: sourceIndex)
        guard let updatedDestinationIndex = groups.firstIndex(where: { $0.id == destinationID }) else { return }
        let insertionIndex = sourceIndex < destinationIndex
            ? updatedDestinationIndex + 1
            : updatedDestinationIndex
        groups.insert(moving, at: insertionIndex)
        save()
    }

    @discardableResult
    public func createGroup(named rawName: String) -> UUID? {
        let name = normalizedName(rawName)
        guard !name.isEmpty, !hasGroup(named: name) else { return nil }
        let group = WatchlistGroup(name: name)
        groups.append(group)
        selectedGroupID = group.id
        save()
        return group.id
    }

    @discardableResult
    public func renameGroup(_ id: UUID, to rawName: String) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        let name = normalizedName(rawName)
        guard !name.isEmpty, !hasGroup(named: name, excluding: id) else { return false }
        groups[index].name = name
        save()
        return true
    }

    /// Deletes only the tag. Instruments that would otherwise become orphaned move to a remaining group.
    @discardableResult
    public func deleteGroup(_ id: UUID) -> Bool {
        guard groups.count > 1, let removedIndex = groups.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let removed = groups.remove(at: removedIndex)
        let fallbackIndex = groups.firstIndex(where: { $0.id == selectedGroupID }) ?? 0
        let stillAssigned = Set(groups.flatMap(\.symbols))
        let orphaned = removed.symbols.filter { !stillAssigned.contains($0) }
        for symbol in orphaned where !groups[fallbackIndex].symbols.contains(symbol) {
            groups[fallbackIndex].symbols.append(symbol)
            if groups[fallbackIndex].manualOrder != nil {
                groups[fallbackIndex].manualOrder?.append(symbol)
            }
        }
        if selectedGroupID == id || group(for: selectedGroupID) == nil {
            selectedGroupID = groups[fallbackIndex].id
        }
        save()
        return true
    }

    public func contains(_ symbol: SymbolID, in groupID: UUID? = nil) -> Bool {
        group(for: groupID ?? selectedGroupID)?.symbols.contains(symbol) == true
    }

    public func item(for symbol: SymbolID) -> WatchItem? {
        allItems.first { $0.symbol == symbol }
    }

    /// Adds to the selected group by default. An existing instrument only gains another tag.
    public func add(_ info: SymbolInfo, to groupID: UUID? = nil) {
        guard let targetID = group(for: groupID ?? selectedGroupID)?.id,
              let groupIndex = groups.firstIndex(where: { $0.id == targetID }) else { return }
        restoreRetainedHistory(for: info.symbol)
        var didUpdateItem = false
        if let itemIndex = allItems.firstIndex(where: { $0.symbol == info.symbol }) {
            if let source = info.displayNameSource,
               shouldAcceptDisplayName(source, over: allItems[itemIndex].displayNameSource) {
                allItems[itemIndex].displayName = info.resolvedDisplayName
                allItems[itemIndex].displayNameSource = source
                didUpdateItem = true
            }
            let candidateType = WatchItem.normalizedInstrumentType(info.type, for: info.symbol)
            if shouldAcceptInstrumentType(
                candidateType,
                over: allItems[itemIndex].instrumentType
            ) {
                allItems[itemIndex].instrumentType = candidateType
                didUpdateItem = true
            }
        } else {
            allItems.append(WatchItem(
                symbol: info.symbol,
                displayName: info.resolvedDisplayName,
                displayNameSource: info.displayNameSource,
                instrumentType: info.type
            ))
        }
        guard !groups[groupIndex].symbols.contains(info.symbol) else {
            if didUpdateItem { save() }
            return
        }
        insertAtTopOfUnpinned(info.symbol, inGroupAt: groupIndex)
        save()
    }

    public func setMembership(_ symbol: SymbolID, in groupID: UUID, included: Bool) {
        guard item(for: symbol) != nil,
              let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if included {
            guard !groups[groupIndex].symbols.contains(symbol) else { return }
            insertAtTopOfUnpinned(symbol, inGroupAt: groupIndex)
        } else {
            guard groups[groupIndex].symbols.contains(symbol) else { return }
            groups[groupIndex].symbols.removeAll { $0 == symbol }
            groups[groupIndex].manualOrder?.removeAll { $0 == symbol }
            groups[groupIndex].pinnedSymbols.removeAll { $0 == symbol }
            if !groups.contains(where: { $0.symbols.contains(symbol) }) {
                if let itemIndex = allItems.firstIndex(where: { $0.symbol == symbol }) {
                    retainHistoryIfNeeded(from: allItems.remove(at: itemIndex))
                }
            }
        }
        save()
    }

    /// Removes an instrument from the selected group. The active item survives in another tag;
    /// after the final removal, its trade history remains dormant until the symbol is added again.
    public func remove(_ symbol: SymbolID) {
        guard let id = selectedGroup?.id else { return }
        setMembership(symbol, in: id, included: false)
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let current = selectedGroup?.symbols else { return }
        let validOffsets = source.filter { current.indices.contains($0) }
        let moving = validOffsets.sorted().map { current[$0] }
        guard !moving.isEmpty else { return }
        let adjusted = destination - validOffsets.filter { $0 < destination }.count
        var orderedSymbols = current
        orderedSymbols.removeAll { moving.contains($0) }
        orderedSymbols.insert(
            contentsOf: moving,
            at: min(max(adjusted, 0), orderedSymbols.count)
        )
        _ = commitManualMove(orderedSymbols: orderedSymbols, movingSymbols: moving)
    }

    /// Atomically commits the final order produced by SwiftUI's native collection move.
    /// Crossing the pinned boundary changes pin membership so the native drop location
    /// and the persisted presentation remain identical.
    @discardableResult
    public func commitManualMove(
        orderedSymbols: [SymbolID],
        movingSymbols: [SymbolID]
    ) -> Bool {
        guard let id = selectedGroup?.id,
              let groupIndex = groups.firstIndex(where: { $0.id == id }) else { return false }

        let currentGroup = groups[groupIndex]
        let currentSet = Set(currentGroup.symbols)
        guard orderedSymbols.count == currentGroup.symbols.count,
              Set(orderedSymbols) == currentSet else { return false }

        let moving = movingSymbols.filter { currentSet.contains($0) }.uniqued()
        let movingSet = Set(moving)
        guard !moving.isEmpty,
              let insertionIndex = orderedSymbols.firstIndex(where: { movingSet.contains($0) }) else {
            return false
        }

        let originalPinned = Set(currentGroup.pinnedSymbols)
        let movingPinnedCount = moving.reduce(into: 0) { count, symbol in
            if originalPinned.contains(symbol) { count += 1 }
        }
        // SwiftUI List currently moves one contiguous selection. Refuse a mixed
        // pinned/unpinned batch rather than committing an invalid interleaved section.
        guard movingPinnedCount == 0 || movingPinnedCount == moving.count else { return false }

        let remainingPinnedCount = originalPinned.count - movingPinnedCount
        var updatedPinned = originalPinned
        if movingPinnedCount == moving.count {
            if insertionIndex > remainingPinnedCount {
                updatedPinned.subtract(movingSet)
            }
        } else if insertionIndex < remainingPinnedCount {
            updatedPinned.formUnion(movingSet)
        }

        var updatedGroup = currentGroup
        updatedGroup.symbols = orderedSymbols
        updatedGroup.pinnedSymbols = orderedSymbols.filter { updatedPinned.contains($0) }
        updatedGroup.manualOrder = manualOrderPreservingPinnedPositions(
            visibleOrder: orderedSymbols,
            pinned: updatedPinned,
            storedOrder: currentGroup.manualOrder
        )
        groups[groupIndex] = updatedGroup
        save()
        return true
    }

    public func reorder(_ orderedSymbols: [SymbolID]) {
        guard let id = selectedGroup?.id,
              let groupIndex = groups.firstIndex(where: { $0.id == id }) else { return }
        let existing = groups[groupIndex].symbols
        let existingSet = Set(existing)
        let ordered = orderedSymbols.filter { existingSet.contains($0) }.uniqued()
        let orderedSet = Set(ordered)
        groups[groupIndex].symbols = ordered + existing.filter { !orderedSet.contains($0) }
        save()
    }

    public func isPinned(_ symbol: SymbolID, in groupID: UUID? = nil) -> Bool {
        group(for: groupID ?? selectedGroupID)?.pinnedSymbols.contains(symbol) == true
    }

    /// Updates only pin membership. The caller decides whether the visible list
    /// should be automatically sorted or manually moved to the top.
    @discardableResult
    public func setPinned(_ symbol: SymbolID, in groupID: UUID? = nil, pinned: Bool) -> Bool {
        guard let targetID = group(for: groupID ?? selectedGroupID)?.id,
              let groupIndex = groups.firstIndex(where: { $0.id == targetID }),
              groups[groupIndex].symbols.contains(symbol) else {
            return false
        }

        let wasPinned = groups[groupIndex].pinnedSymbols.contains(symbol)
        guard wasPinned != pinned else { return false }
        if pinned {
            groups[groupIndex].pinnedSymbols.insert(symbol, at: 0)
        } else {
            groups[groupIndex].pinnedSymbols.removeAll { $0 == symbol }
        }
        save()
        return true
    }

    public func rememberManualOrder() {
        guard let id = selectedGroup?.id,
              let groupIndex = groups.firstIndex(where: { $0.id == id }) else { return }
        var updatedGroup = groups[groupIndex]
        let pinned = Set(updatedGroup.pinnedSymbols)
        updatedGroup.manualOrder = manualOrderPreservingPinnedPositions(
            visibleOrder: updatedGroup.symbols,
            pinned: pinned,
            storedOrder: updatedGroup.manualOrder
        )
        updatedGroup.pinnedSymbols = updatedGroup.symbols
            .filter { pinned.contains($0) }
            .uniqued()
        groups[groupIndex] = updatedGroup
        save()
    }

    @discardableResult
    public func restoreManualOrder() -> Bool {
        guard let id = selectedGroup?.id,
              let groupIndex = groups.firstIndex(where: { $0.id == id }),
              let manualOrder = groups[groupIndex].manualOrder,
              !manualOrder.isEmpty else { return false }
        let existing = groups[groupIndex].symbols
        let existingSet = Set(existing)
        let ordered = manualOrder.filter { existingSet.contains($0) }.uniqued()
        let orderedSet = Set(ordered)
        groups[groupIndex].symbols = ordered + existing.filter { !orderedSet.contains($0) }
        save()
        return true
    }

    public func updateLots(_ symbol: SymbolID, lots: [CostLot]) {
        guard let index = allItems.firstIndex(where: { $0.symbol == symbol }) else { return }
        // Preserve legacy index data until the user explicitly removes it, but
        // never create or replace a position for a non-tradable index.
        guard allItems[index].supportsPosition || lots.isEmpty else { return }
        allItems[index].lots = lots
        save()
    }

    /// Clears the open position. Items with transaction history keep it —
    /// the ledger records a zero adjustment so realized P&L and the trade log
    /// survive; legacy lot-only items are wiped as before.
    public func clearPosition(_ symbol: SymbolID) {
        guard let index = allItems.firstIndex(where: { $0.symbol == symbol }) else { return }
        guard !allItems[index].transactions.isEmpty else {
            updateLots(symbol, lots: [])
            return
        }
        calibratePosition(symbol, quantity: 0, averageCost: 0)
    }

    // MARK: - Transactions

    /// Appends a trade. The first transaction on a lot-based item folds the
    /// legacy position into the ledger as an opening adjustment.
    public func addTransaction(_ symbol: SymbolID, _ transaction: PositionTransaction) {
        guard let index = allItems.firstIndex(where: { $0.symbol == symbol }),
              allItems[index].supportsPosition,
              transaction.quantity > 0, transaction.price > 0 else { return }
        var transactions = allItems[index].materializedTransactions()
        transactions.append(transaction)
        commitTransactions(transactions, at: index)
    }

    public func deleteTransaction(_ symbol: SymbolID, id: UUID) {
        guard let index = allItems.firstIndex(where: { $0.symbol == symbol }) else { return }
        var transactions = allItems[index].transactions
        let count = transactions.count
        transactions.removeAll { $0.id == id }
        guard transactions.count != count else { return }
        commitTransactions(transactions, at: index)
    }

    /// Overwrites the position with a target quantity and average cost as an
    /// `.adjustment` entry ("quick set" / reconciling with a broker). A
    /// negative quantity calibrates a short. Produces no realized P&L.
    public func calibratePosition(
        _ symbol: SymbolID,
        quantity: Double,
        averageCost: Double,
        date: Date = .now
    ) {
        guard let index = allItems.firstIndex(where: { $0.symbol == symbol }),
              allItems[index].supportsPosition,
              quantity.isFinite, averageCost >= 0 else { return }
        var transactions = allItems[index].materializedTransactions()
        transactions.append(PositionTransaction(
            kind: .adjustment,
            price: averageCost,
            quantity: quantity,
            date: date
        ))
        commitTransactions(transactions, at: index)
    }

    /// Stores the replay-ordered list and refreshes the derived single-lot
    /// cache so lot-based consumers (rows, sharing, older builds) keep seeing
    /// the open position. A short caches as a negative-quantity lot, which
    /// older builds simply treat as no position rather than corrupting it.
    private func commitTransactions(_ transactions: [PositionTransaction], at index: Int) {
        applyTransactions(transactions, at: index)
        save()
    }

    /// Replays a ledger onto an item and refreshes its derived single-lot cache.
    /// Split out from `commitTransactions` so a bulk import can apply many items
    /// before persisting once.
    private func applyTransactions(_ transactions: [PositionTransaction], at index: Int) {
        allItems[index].transactions = PositionLedger.replayOrdered(transactions)
        let ledger = PositionLedger(transactions: allItems[index].transactions)
        allItems[index].lots = ledger.hasOpenPosition
            ? [CostLot(price: ledger.averageCost, quantity: ledger.quantity, date: nil)]
            : []
    }

    /// Replaces a persisted name only when its provider outranks the saved source.
    /// Static reference data may refresh a name from the same provider (for a
    /// locale change or an official rename); quote ticks never need that privilege.
    @discardableResult
    public func upgradeDisplayName(
        for symbol: SymbolID,
        to rawName: String,
        source: DisplayNameSource,
        allowSameProviderRefresh: Bool = false
    ) -> Bool {
        guard symbol.indexID == nil, symbol.metalID == nil,
              let index = allItems.firstIndex(where: { $0.symbol == symbol }) else {
            return false
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        let currentSource = allItems[index].displayNameSource
        let currentName = allItems[index].displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPlaceholderName = currentName.isEmpty
            || currentName.caseInsensitiveCompare(symbol.code) == .orderedSame
            || currentName.caseInsensitiveCompare(symbol.displayCode) == .orderedSame
        // Legacy watchlists have no provenance. Preserve a real saved name
        // against quote ticks; authoritative static data may adopt and rank it.
        let isUpgrade = currentSource.map { source.priority < $0.priority }
            ?? (allowSameProviderRefresh || hasPlaceholderName)
        let isSameProviderRefresh = allowSameProviderRefresh
            && currentSource?.providerID == source.providerID
            && currentSource?.priority == source.priority
        guard isUpgrade || isSameProviderRefresh else { return false }
        guard allItems[index].displayName != name || currentSource != source else { return false }

        allItems[index].displayName = name
        allItems[index].displayNameSource = source
        save()
        return true
    }

    // MARK: - Archive

    /// The current watchlists in portable form, in the order they are shown.
    public func archive(exportedAt: Date = .now, app: String? = nil) -> WatchlistArchive {
        let itemsBySymbol = Dictionary(uniqueKeysWithValues: allItems.map { ($0.symbol, $0) })
        let lists = groups.map { group in
            let pinned = Set(group.pinnedSymbols)
            let entries = group.symbols.compactMap { symbol -> WatchlistArchive.Entry? in
                guard let item = itemsBySymbol[symbol] else { return nil }
                return WatchlistArchive.Entry(
                    market: symbol.market,
                    code: symbol.code,
                    name: item.displayName,
                    type: item.instrumentType,
                    pinned: pinned.contains(symbol) ? true : nil,
                    // Positions recorded before the ledger existed live only in the
                    // legacy lot cache. Materializing here is what keeps them in the
                    // archive instead of silently exporting a position-less entry.
                    transactions: item.materializedTransactions().isEmpty
                        ? nil
                        : item.materializedTransactions()
                )
            }
            return WatchlistArchive.List(name: group.name, entries: entries)
        }
        return WatchlistArchive(exportedAt: exportedAt, app: app, lists: lists)
    }

    /// What importing `archive` would do, entry by entry, without writing anything.
    /// The settings screen shows this before asking for confirmation so the user can
    /// see the instruments Pulse understood rather than the text they pasted.
    public func importPlan(for archive: WatchlistArchive) -> WatchlistArchive.ImportPlan {
        var listPlans: [WatchlistArchive.ImportPlan.ListPlan] = []
        var itemID = 0

        for (listIndex, list) in archive.lists.enumerated() {
            let name = normalizedName(list.name)
            let existing = groups.first { $0.name == name }
            // Membership accumulates while planning so a list that repeats a symbol
            // reports the second mention as already present rather than a second add.
            var plannedSymbols = Set(existing?.symbols ?? [])

            var items: [WatchlistArchive.ImportPlan.Item] = []
            for entry in list.entries {
                itemID += 1
                let resolution = entry.resolution
                let outcome: WatchlistArchive.ImportPlan.Outcome
                switch resolution {
                case .unknownMarket, .missingCode:
                    outcome = .skipped(resolution)
                case .resolved(let symbol):
                    if plannedSymbols.contains(symbol) {
                        let hasEmptyLedger = item(for: symbol)?.materializedTransactions().isEmpty ?? false
                        let bringsTrades = !(entry.transactions ?? []).isEmpty
                        outcome = hasEmptyLedger && bringsTrades
                            ? .restorePosition(symbol)
                            : .alreadyInList(symbol)
                    } else {
                        plannedSymbols.insert(symbol)
                        outcome = .add(symbol)
                    }
                }
                items.append(.init(id: itemID, entry: entry, outcome: outcome))
            }

            listPlans.append(.init(
                id: listIndex,
                name: name.isEmpty ? list.name : name,
                isNew: existing == nil && !name.isEmpty,
                items: items
            ))
        }

        return WatchlistArchive.ImportPlan(lists: listPlans)
    }

    /// Adds everything in `archive` that is missing. Import is deliberately additive:
    /// it never removes a list, a symbol, or a trade, so importing a stale backup
    /// cannot destroy newer work and re-importing the same archive is a no-op.
    ///
    /// A symbol already on the watchlist keeps its saved name, and an instrument that
    /// already has trades keeps them — the archive only fills positions that are empty.
    /// An entry Pulse cannot resolve is skipped on its own; it never fails the import.
    @discardableResult
    public func merge(_ archive: WatchlistArchive) -> WatchlistArchive.ImportPlan {
        let plan = importPlan(for: archive)

        for (list, listPlan) in zip(archive.lists, plan.lists) {
            let name = normalizedName(list.name)
            guard !name.isEmpty else { continue }

            let groupIndex: Int
            if let existing = groups.firstIndex(where: { $0.name == name }) {
                groupIndex = existing
            } else {
                groups.append(WatchlistGroup(name: name))
                groupIndex = groups.count - 1
            }

            var appended: [SymbolID] = []
            for planItem in listPlan.items {
                guard let symbol = planItem.symbol else { continue }
                let entry = planItem.entry
                let archivedTransactions = entry.transactions ?? []
                restoreRetainedHistory(for: symbol)

                if let itemIndex = allItems.firstIndex(where: { $0.symbol == symbol }) {
                    // Only an empty position adopts the archive's trades; a live
                    // ledger is never overwritten by an import.
                    // A legacy lot-only position is a real position: it must not read as
                    // an empty ledger the archive is free to fill.
                    if allItems[itemIndex].materializedTransactions().isEmpty,
                       !archivedTransactions.isEmpty {
                        applyTransactions(archivedTransactions, at: itemIndex)
                    }
                } else {
                    let archivedName = entry.name?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    allItems.append(WatchItem(
                        symbol: symbol,
                        // An entry without a name keeps the code as a placeholder and
                        // no provenance, which is exactly the state the existing
                        // display-name upgrade path repairs on the first refresh.
                        displayName: archivedName.isEmpty ? symbol.displayCode : archivedName,
                        displayNameSource: nil,
                        instrumentType: entry.type
                    ))
                    if !archivedTransactions.isEmpty {
                        applyTransactions(archivedTransactions, at: allItems.count - 1)
                    }
                }

                if case .add = planItem.outcome, !groups[groupIndex].symbols.contains(symbol) {
                    appended.append(symbol)
                }
                if entry.pinned == true, !groups[groupIndex].pinnedSymbols.contains(symbol) {
                    groups[groupIndex].pinnedSymbols.append(symbol)
                }
            }

            // Appending preserves the archive's own order. `add(_:to:)` inserts at the
            // top, which would silently reverse an imported list.
            groups[groupIndex].symbols.append(contentsOf: appended)
            if groups[groupIndex].manualOrder != nil {
                groups[groupIndex].manualOrder?.append(contentsOf: appended)
            }
        }

        normalizeLoadedState()
        if group(for: selectedGroupID) == nil {
            selectedGroupID = groups.first?.id
        }
        save()
        return plan
    }

    private struct Snapshot: Codable {
        var items: [WatchItem]
        var groups: [WatchlistGroup]
        var selectedGroupID: UUID?
        /// Optional so snapshots written before removed-history retention still decode.
        var retainedHistoryItems: [WatchItem]?
    }

    private func load() {
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            allItems = snapshot.items
            groups = snapshot.groups
            selectedGroupID = snapshot.selectedGroupID
            retainedHistoryItems = snapshot.retainedHistoryItems ?? []
            normalizeLoadedState()
            save()
            return
        }
        migrateLegacyState()
    }

    private func migrateLegacyState() {
        if let data = defaults.data(forKey: legacyStorageKey),
           let decoded = try? JSONDecoder().decode([WatchItem].self, from: data) {
            allItems = decoded
        }
        let symbols = allItems.map(\.symbol).uniqued()
        var manualOrder: [SymbolID]?
        if let data = defaults.data(forKey: legacyManualOrderKey),
           let decoded = try? JSONDecoder().decode([SymbolID].self, from: data) {
            let known = Set(symbols)
            let ordered = decoded.filter { known.contains($0) }.uniqued()
            let orderedSet = Set(ordered)
            manualOrder = ordered + symbols.filter { !orderedSet.contains($0) }

            // Keep the legacy payload readable by the immediately preceding app version.
            if let encoded = try? JSONEncoder().encode(manualOrder) {
                defaults.set(encoded, forKey: legacyManualOrderKey)
            }
        }
        let group = WatchlistGroup(name: initialGroupName, symbols: symbols, manualOrder: manualOrder)
        groups = [group]
        selectedGroupID = group.id

        // Re-encoding also advances legacy crypto identifiers before v2 takes ownership.
        if let encoded = try? JSONEncoder().encode(allItems) {
            defaults.set(encoded, forKey: legacyStorageKey)
        }
        save()
    }

    private func normalizeLoadedState() {
        // Provider-specific legacy index aliases can now decode to the same
        // canonical SymbolID. Merge them instead of dropping the later entry and
        // silently losing any position lots attached to it.
        let activeSymbols = Set(allItems.map(\.symbol))
        let normalizedStoredItems = normalizedItems(allItems + retainedHistoryItems)
        allItems = normalizedStoredItems.filter { activeSymbols.contains($0.symbol) }
        retainedHistoryItems = normalizedStoredItems.filter {
            !activeSymbols.contains($0.symbol) && !$0.materializedTransactions().isEmpty
        }

        if groups.isEmpty {
            groups = [WatchlistGroup(name: initialGroupName, symbols: allItems.map(\.symbol))]
        }

        let known = Set(allItems.map(\.symbol))
        for index in groups.indices {
            groups[index].name = normalizedName(groups[index].name)
            if groups[index].name.isEmpty { groups[index].name = initialGroupName }
            groups[index].symbols = groups[index].symbols.filter { known.contains($0) }.uniqued()
            if let manualOrder = groups[index].manualOrder {
                groups[index].manualOrder = manualOrder.filter { known.contains($0) }.uniqued()
            }
            let members = Set(groups[index].symbols)
            groups[index].pinnedSymbols = groups[index].pinnedSymbols
                .filter { members.contains($0) }
                .uniqued()
        }

        let assigned = Set(groups.flatMap(\.symbols))
        for symbol in allItems.map(\.symbol) where !assigned.contains(symbol) {
            groups[0].symbols.append(symbol)
        }
        if group(for: selectedGroupID) == nil {
            selectedGroupID = groups[0].id
        }
    }

    private func normalizedItems(_ storedItems: [WatchItem]) -> [WatchItem] {
        var normalizedItems: [WatchItem] = []
        var itemIndexBySymbol: [SymbolID: Int] = [:]
        for var item in storedItems {
            item.instrumentType = WatchItem.normalizedInstrumentType(
                item.instrumentType,
                for: item.symbol
            )
            if let existingIndex = itemIndexBySymbol[item.symbol] {
                var existingLotIDs = Set(normalizedItems[existingIndex].lots.map(\.id))
                normalizedItems[existingIndex].lots.append(
                    contentsOf: item.lots.filter { existingLotIDs.insert($0.id).inserted }
                )
                var existingTransactionIDs = Set(normalizedItems[existingIndex].transactions.map(\.id))
                normalizedItems[existingIndex].transactions = PositionLedger.replayOrdered(
                    normalizedItems[existingIndex].transactions + item.transactions.filter {
                        existingTransactionIDs.insert($0.id).inserted
                    }
                )
                normalizedItems[existingIndex].addedAt = min(
                    normalizedItems[existingIndex].addedAt,
                    item.addedAt
                )
                if let source = item.displayNameSource,
                   shouldAcceptDisplayName(
                       source,
                       over: normalizedItems[existingIndex].displayNameSource
                   ) {
                    normalizedItems[existingIndex].displayName = item.displayName
                    normalizedItems[existingIndex].displayNameSource = source
                }
                if shouldAcceptInstrumentType(
                    item.instrumentType,
                    over: normalizedItems[existingIndex].instrumentType
                ) {
                    normalizedItems[existingIndex].instrumentType = item.instrumentType
                }
            } else {
                itemIndexBySymbol[item.symbol] = normalizedItems.count
                normalizedItems.append(item)
            }
        }
        return normalizedItems
    }

    private func save() {
        let snapshot = Snapshot(
            items: allItems,
            groups: groups,
            selectedGroupID: selectedGroupID,
            retainedHistoryItems: retainedHistoryItems
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Keeps removed ledger data outside the active watchlist so it neither renders nor refreshes.
    private func retainHistoryIfNeeded(from item: WatchItem) {
        guard !item.materializedTransactions().isEmpty else { return }
        retainedHistoryItems = normalizedItems(retainedHistoryItems + [item])
    }

    /// Rehydrates the original item before normal add/update logic refreshes its metadata.
    private func restoreRetainedHistory(for symbol: SymbolID) {
        guard allItems.allSatisfy({ $0.symbol != symbol }),
              let index = retainedHistoryItems.firstIndex(where: { $0.symbol == symbol }) else {
            return
        }
        allItems.append(retainedHistoryItems.remove(at: index))
    }

    /// Rebuilds the hidden custom-order baseline from a visible pinned-first order.
    /// Pinned symbols keep their baseline slots; regular symbols adopt their visible
    /// relative order. With no pins, the visible order is the baseline directly.
    private func manualOrderPreservingPinnedPositions(
        visibleOrder: [SymbolID],
        pinned: Set<SymbolID>,
        storedOrder: [SymbolID]?
    ) -> [SymbolID] {
        guard !pinned.isEmpty else { return visibleOrder }

        let visibleSet = Set(visibleOrder)
        let stored = (storedOrder ?? visibleOrder)
            .filter { visibleSet.contains($0) }
            .uniqued()
        let storedSet = Set(stored)
        let baselineOrder = stored + visibleOrder.filter { !storedSet.contains($0) }
        let visibleUnpinned = visibleOrder.filter { !pinned.contains($0) }
        var unpinnedIndex = 0
        var updatedBaseline: [SymbolID] = []
        updatedBaseline.reserveCapacity(baselineOrder.count)

        for symbol in baselineOrder {
            if pinned.contains(symbol) {
                updatedBaseline.append(symbol)
            } else if unpinnedIndex < visibleUnpinned.count {
                updatedBaseline.append(visibleUnpinned[unpinnedIndex])
                unpinnedIndex += 1
            }
        }
        return updatedBaseline.uniqued()
    }

    /// New members lead the regular section without displacing pinned symbols.
    /// Keep the hidden custom-order baseline in sync so restoring or unpinning
    /// cannot send a newly added symbol back to the bottom.
    private func insertAtTopOfUnpinned(_ symbol: SymbolID, inGroupAt groupIndex: Int) {
        var updatedGroup = groups[groupIndex]
        let pinned = Set(updatedGroup.pinnedSymbols)
        let existingSymbols = updatedGroup.symbols
        let visiblePinned = existingSymbols.filter { pinned.contains($0) }
        let visibleUnpinned = existingSymbols.filter { !pinned.contains($0) }
        updatedGroup.symbols = visiblePinned + [symbol] + visibleUnpinned

        if let storedOrder = updatedGroup.manualOrder {
            let existingSet = Set(existingSymbols)
            let normalizedOrder = storedOrder
                .filter { existingSet.contains($0) }
                .uniqued()
            let normalizedSet = Set(normalizedOrder)
            var manualOrder = normalizedOrder + existingSymbols.filter {
                !normalizedSet.contains($0)
            }
            let baselineInsertionIndex = manualOrder.firstIndex {
                !pinned.contains($0)
            } ?? manualOrder.endIndex
            manualOrder.insert(symbol, at: baselineInsertionIndex)
            updatedGroup.manualOrder = manualOrder.uniqued()
        }

        groups[groupIndex] = updatedGroup
    }

    private func normalizedName(_ rawName: String) -> String {
        String(rawName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
    }

    private func hasGroup(named name: String, excluding excludedID: UUID? = nil) -> Bool {
        groups.contains {
            $0.id != excludedID && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func shouldAcceptDisplayName(
        _ candidate: DisplayNameSource,
        over current: DisplayNameSource?
    ) -> Bool {
        guard let current else { return true }
        return candidate.priority < current.priority
    }

    private func shouldAcceptInstrumentType(
        _ candidate: InstrumentType?,
        over current: InstrumentType?
    ) -> Bool {
        guard let candidate, candidate != .other else { return false }
        return current == nil || current == .other
    }

    private static var localizedDefaultGroupName: String {
        let key = "watchlist.defaultName"
        let localized = PulseLocalization.localizedString(key)
        guard localized == key else { return localized }
        return PulseLocalization.currentLanguageIdentifier.hasPrefix("zh") ? "自选" : "Watchlist"
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
