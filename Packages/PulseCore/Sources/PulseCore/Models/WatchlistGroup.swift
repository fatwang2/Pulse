import Foundation

/// A named watchlist tag. Instruments remain globally unique; groups only store membership and order.
public struct WatchlistGroup: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbols: [SymbolID]
    public var manualOrder: [SymbolID]?
    /// Symbols kept ahead of the selected metric sort in this group. Pinning is
    /// group-scoped because the same instrument may belong to several groups.
    public var pinnedSymbols: [SymbolID]

    public init(
        id: UUID = UUID(),
        name: String,
        symbols: [SymbolID] = [],
        manualOrder: [SymbolID]? = nil,
        pinnedSymbols: [SymbolID] = []
    ) {
        self.id = id
        self.name = name
        self.symbols = symbols
        self.manualOrder = manualOrder
        self.pinnedSymbols = pinnedSymbols
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbols, manualOrder, pinnedSymbols
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbols = try container.decode([SymbolID].self, forKey: .symbols)
        manualOrder = try container.decodeIfPresent([SymbolID].self, forKey: .manualOrder)
        pinnedSymbols = try container.decodeIfPresent([SymbolID].self, forKey: .pinnedSymbols) ?? []
    }
}
