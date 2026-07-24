import Foundation
import Observation

/// Watchlist instruments plus named tag membership, backed by UserDefaults.
/// Instruments and positions are stored once even when they appear in several groups.
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
        groups[groupIndex].symbols.append(info.symbol)
        if groups[groupIndex].manualOrder != nil {
            groups[groupIndex].manualOrder?.append(info.symbol)
        }
        save()
    }

    public func setMembership(_ symbol: SymbolID, in groupID: UUID, included: Bool) {
        guard item(for: symbol) != nil,
              let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if included {
            guard !groups[groupIndex].symbols.contains(symbol) else { return }
            groups[groupIndex].symbols.append(symbol)
            if groups[groupIndex].manualOrder != nil {
                groups[groupIndex].manualOrder?.append(symbol)
            }
        } else {
            guard groups[groupIndex].symbols.contains(symbol) else { return }
            groups[groupIndex].symbols.removeAll { $0 == symbol }
            groups[groupIndex].manualOrder?.removeAll { $0 == symbol }
            if !groups.contains(where: { $0.symbols.contains(symbol) }) {
                allItems.removeAll { $0.symbol == symbol }
            }
        }
        save()
    }

    /// Removes an instrument from the selected group. Its position survives while another tag contains it.
    public func remove(_ symbol: SymbolID) {
        guard let id = selectedGroup?.id else { return }
        setMembership(symbol, in: id, included: false)
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let id = selectedGroup?.id,
              let groupIndex = groups.firstIndex(where: { $0.id == id }) else { return }
        let current = groups[groupIndex].symbols
        let validOffsets = source.filter { current.indices.contains($0) }
        let moving = validOffsets.sorted().map { current[$0] }
        let adjusted = destination - validOffsets.filter { $0 < destination }.count
        groups[groupIndex].symbols.removeAll { moving.contains($0) }
        groups[groupIndex].symbols.insert(
            contentsOf: moving,
            at: min(max(adjusted, 0), groups[groupIndex].symbols.count)
        )
        save()
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

    public func rememberManualOrder() {
        guard let id = selectedGroup?.id,
              let groupIndex = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[groupIndex].manualOrder = groups[groupIndex].symbols
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

    public func clearPosition(_ symbol: SymbolID) {
        updateLots(symbol, lots: [])
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
        guard symbol.indexID == nil,
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

    private struct Snapshot: Codable {
        var items: [WatchItem]
        var groups: [WatchlistGroup]
        var selectedGroupID: UUID?
    }

    private func load() {
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            allItems = snapshot.items
            groups = snapshot.groups
            selectedGroupID = snapshot.selectedGroupID
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
        var normalizedItems: [WatchItem] = []
        var itemIndexBySymbol: [SymbolID: Int] = [:]
        for var item in allItems {
            item.instrumentType = WatchItem.normalizedInstrumentType(
                item.instrumentType,
                for: item.symbol
            )
            if let existingIndex = itemIndexBySymbol[item.symbol] {
                var existingLotIDs = Set(normalizedItems[existingIndex].lots.map(\.id))
                normalizedItems[existingIndex].lots.append(
                    contentsOf: item.lots.filter { existingLotIDs.insert($0.id).inserted }
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
        allItems = normalizedItems
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
        }

        let assigned = Set(groups.flatMap(\.symbols))
        for symbol in allItems.map(\.symbol) where !assigned.contains(symbol) {
            groups[0].symbols.append(symbol)
        }
        if group(for: selectedGroupID) == nil {
            selectedGroupID = groups[0].id
        }
    }

    private func save() {
        let snapshot = Snapshot(items: allItems, groups: groups, selectedGroupID: selectedGroupID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
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
