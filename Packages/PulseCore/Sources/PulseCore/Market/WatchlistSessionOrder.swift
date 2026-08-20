import Foundation

/// Presentation buckets for schedule-aware watchlist ordering.
/// Shanghai and Shenzhen share one China A block so A-shares never interleave with other markets.
public enum MarketBlock: String, Sendable, Hashable, CaseIterable {
    case chinaA
    case hk
    case us
    case jp
    /// Both Korea Exchange boards, the way `chinaA` holds both Chinese ones.
    case korea
    case metal
    case crypto

    public init(market: Market) {
        switch market {
        case .sh, .sz: self = .chinaA
        case .hk: self = .hk
        case .us: self = .us
        case .jp: self = .jp
        case .kr, .kq: self = .korea
        case .metal, .metalCN: self = .metal
        case .crypto: self = .crypto
        }
    }
}

/// Beijing-time watchlist layout. Daytime follows Asia; evening follows the US session.
public enum MarketScheduleWindow: String, Sendable, Hashable {
    /// 08:00..<17:00 Asia/Shanghai → HK → China A → Japan → Korea → US → metals → crypto
    case asiaDay
    /// 17:00..<08:00 Asia/Shanghai → US → HK → China A → Japan → Korea → metals → crypto
    case usEvening

    public static var beijingTimeZone: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }

    public static func at(_ date: Date = .now, timeZone: TimeZone = beijingTimeZone) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return (8..<17).contains(hour) ? .asiaDay : .usEvening
    }

    public var blockOrder: [MarketBlock] {
        switch self {
        // Metals and crypto trade around the clock, so no schedule window can
        // promote them; they stay after the session-bound blocks.
        // Tokyo and Seoul open at 08:00 Beijing, ahead of both Chinese markets,
        // but they sit behind them here: opening first does not make them the
        // block a Pulse user is watching.
        case .asiaDay: [.hk, .chinaA, .jp, .korea, .us, .metal, .crypto]
        case .usEvening: [.us, .hk, .chinaA, .jp, .korea, .metal, .crypto]
        }
    }
}

/// Rebuilds a watchlist into market blocks for the current Beijing-time window.
/// Pins stay inside each block; relative order inside each pin/unpinned slice
/// comes from the caller’s base sequence.
public enum WatchlistSessionOrder {
    public static func orderedSymbols(
        _ symbols: [SymbolID],
        pinned: Set<SymbolID> = [],
        at date: Date = .now,
        timeZone: TimeZone = MarketScheduleWindow.beijingTimeZone
    ) -> [SymbolID] {
        guard !symbols.isEmpty else { return [] }

        var blockSymbols: [MarketBlock: [SymbolID]] = [:]
        for symbol in symbols {
            blockSymbols[MarketBlock(market: symbol.market), default: []].append(symbol)
        }

        let ranking = Dictionary(
            uniqueKeysWithValues: MarketScheduleWindow.at(date, timeZone: timeZone)
                .blockOrder
                .enumerated()
                .map { ($0.element, $0.offset) }
        )

        let sortedBlocks = blockSymbols.keys.sorted {
            (ranking[$0] ?? .max) < (ranking[$1] ?? .max)
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
        timeZone: TimeZone = MarketScheduleWindow.beijingTimeZone
    ) -> [WatchItem] {
        let order = orderedSymbols(
            items.map(\.symbol),
            pinned: pinned,
            at: date,
            timeZone: timeZone
        )
        let bySymbol = Dictionary(uniqueKeysWithValues: items.map { ($0.symbol, $0) })
        return order.compactMap { bySymbol[$0] }
    }
}
