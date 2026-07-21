import Foundation

/// A named watchlist tag. Instruments remain globally unique; groups only store membership and order.
public struct WatchlistGroup: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbols: [SymbolID]
    public var manualOrder: [SymbolID]?

    public init(
        id: UUID = UUID(),
        name: String,
        symbols: [SymbolID] = [],
        manualOrder: [SymbolID]? = nil
    ) {
        self.id = id
        self.name = name
        self.symbols = symbols
        self.manualOrder = manualOrder
    }
}
