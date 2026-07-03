import Foundation
import Observation

/// Watchlist: in-memory state + UserDefaults persistence.
/// The suite is injectable — switching to an App Group container (shared with widgets) in the release build only touches one place.
@MainActor
@Observable
public final class WatchlistStore {
    public private(set) var items: [WatchItem] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "pulse.watchlist.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public var symbols: [SymbolID] { items.map(\.symbol) }

    public var isEmpty: Bool { items.isEmpty }

    public func contains(_ symbol: SymbolID) -> Bool {
        items.contains { $0.symbol == symbol }
    }

    public func item(for symbol: SymbolID) -> WatchItem? {
        items.first { $0.symbol == symbol }
    }

    public func add(_ info: SymbolInfo) {
        guard !contains(info.symbol) else { return }
        items.append(WatchItem(symbol: info.symbol, displayName: info.name))
        save()
    }

    public func remove(_ symbol: SymbolID) {
        items.removeAll { $0.symbol == symbol }
        save()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Equivalent to SwiftUI's move(fromOffsets:toOffset:); implemented manually because PulseCore doesn't depend on SwiftUI
        let moving = source.sorted().map { items[$0] }
        let adjusted = destination - source.filter { $0 < destination }.count
        items.removeAll { item in moving.contains { $0.id == item.id } }
        items.insert(contentsOf: moving, at: min(adjusted, items.count))
        save()
    }

    public func updateDisplayName(_ symbol: SymbolID, name: String) {
        guard let index = items.firstIndex(where: { $0.symbol == symbol }),
              items[index].displayName != name else { return }
        items[index].displayName = name
        save()
    }

    public func updateLots(_ symbol: SymbolID, lots: [CostLot]) {
        guard let index = items.firstIndex(where: { $0.symbol == symbol }) else { return }
        items[index].lots = lots
        save()
    }

    public func clearPosition(_ symbol: SymbolID) {
        updateLots(symbol, lots: [])
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        items = (try? JSONDecoder().decode([WatchItem].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
