import Foundation

/// Presentation buckets for session-aware watchlist ordering.
/// Shanghai and Shenzhen share one China A block so A-shares never interleave with other markets.
public enum MarketBlock: String, Sendable, Hashable, CaseIterable, Comparable {
    case chinaA
    case hk
    case us
    case crypto

    public init(market: Market) {
        switch market {
        case .sh, .sz: self = .chinaA
        case .hk: self = .hk
        case .us: self = .us
        case .crypto: self = .crypto
        }
    }

    /// Stable left-to-right order among open (or among closed) blocks.
    public var sortIndex: Int {
        switch self {
        case .chinaA: 0
        case .hk: 1
        case .us: 2
        case .crypto: 3
        }
    }

    public static func < (lhs: MarketBlock, rhs: MarketBlock) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }
}

/// Rebuilds a watchlist into market blocks: open sessions first, pins inside each block,
/// relative order inside each pin/unpinned slice taken from the caller’s base sequence.
public enum WatchlistSessionOrder {
    public static func orderedSymbols(
        _ symbols: [SymbolID],
        pinned: Set<SymbolID> = [],
        at date: Date = .now,
        priority: (Market, Date) -> Bool = TradingCalendar.hasSessionPriority
    ) -> [SymbolID] {
        guard !symbols.isEmpty else { return [] }

        var blockSymbols: [MarketBlock: [SymbolID]] = [:]
        var blockOrder: [MarketBlock] = []
        for symbol in symbols {
            let block = MarketBlock(market: symbol.market)
            if blockSymbols[block] == nil {
                blockOrder.append(block)
                blockSymbols[block] = []
            }
            blockSymbols[block, default: []].append(symbol)
        }

        let sortedBlocks = blockOrder.sorted { lhs, rhs in
            let leftOpen = priority(representativeMarket(for: lhs), date)
            let rightOpen = priority(representativeMarket(for: rhs), date)
            if leftOpen != rightOpen { return leftOpen }
            return lhs < rhs
        }

        return sortedBlocks.flatMap { block in
            let members = blockSymbols[block] ?? []
            let pinnedMembers = members.filter { pinned.contains($0) }
            let unpinnedMembers = members.filter { !pinned.contains($0) }
            return pinnedMembers + unpinnedMembers
        }
    }

    public static func orderedItems(
        _ items: [WatchItem],
        pinned: Set<SymbolID> = [],
        at date: Date = .now,
        priority: (Market, Date) -> Bool = TradingCalendar.hasSessionPriority
    ) -> [WatchItem] {
        let order = orderedSymbols(
            items.map(\.symbol),
            pinned: pinned,
            at: date,
            priority: priority
        )
        let bySymbol = Dictionary(uniqueKeysWithValues: items.map { ($0.symbol, $0) })
        return order.compactMap { bySymbol[$0] }
    }

    private static func representativeMarket(for block: MarketBlock) -> Market {
        switch block {
        case .chinaA: .sh
        case .hk: .hk
        case .us: .us
        case .crypto: .crypto
        }
    }
}
