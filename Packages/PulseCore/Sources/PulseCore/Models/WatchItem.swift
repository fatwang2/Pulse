import Foundation

/// A cost lot (data foundation for the V0.2 P&L feature; the MVP keeps the fields but has no UI)
public struct CostLot: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var price: Double
    public var quantity: Double
    public var date: Date?

    public init(id: UUID = UUID(), price: Double, quantity: Double, date: Date? = nil) {
        self.id = id
        self.price = price
        self.quantity = quantity
        self.date = date
    }
}

/// A watchlist entry
public struct WatchItem: Codable, Sendable, Hashable, Identifiable {
    public var symbol: SymbolID
    /// Name captured when the item was added (fallback for offline/first-frame display; the latest name from quotes takes precedence)
    public var displayName: String
    public var addedAt: Date
    public var lots: [CostLot]

    public init(symbol: SymbolID, displayName: String, addedAt: Date = .now, lots: [CostLot] = []) {
        self.symbol = symbol
        self.displayName = displayName
        self.addedAt = addedAt
        self.lots = lots
    }

    public var id: SymbolID { symbol }
}
