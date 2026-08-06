import Foundation
import PulseCore

/// Presentation-only watchlist order. Leaves persisted `group.symbols` / `manualOrder` alone.
enum WatchlistDisplayOrder {
    @MainActor
    static func items(
        from watchlist: WatchlistStore,
        prioritizeOpenMarkets: Bool,
        at date: Date = .now,
        bypass: Bool = false
    ) -> [WatchItem] {
        let base = watchlist.items
        guard prioritizeOpenMarkets, !bypass, !base.isEmpty else { return base }
        let pinned = Set(watchlist.selectedGroup?.pinnedSymbols ?? [])
        return WatchlistSessionOrder.orderedItems(base, pinned: pinned, at: date)
    }
}
