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
    /// Stable name captured when the item was added. Quote-source failover does
    /// not replace it.
    public var displayName: String
    /// Provider and priority watermark that supplied `displayName`. Missing on
    /// watchlists written by older Pulse versions and upgraded on first refresh.
    public var displayNameSource: DisplayNameSource?
    /// Search/reference-data classification captured independently from the
    /// provider-specific quote symbol. Older watchlists may not have this field.
    public var instrumentType: InstrumentType?
    public var addedAt: Date
    /// Legacy position storage, kept as a derived single-lot cache once
    /// `transactions` exist so older builds and lot-based consumers keep
    /// seeing the open position. Items untouched since the transaction
    /// upgrade still carry their original lots verbatim.
    public var lots: [CostLot]
    /// Source of truth for the position once non-empty (see `PositionLedger`).
    public var transactions: [PositionTransaction]

    public init(
        symbol: SymbolID,
        displayName: String,
        displayNameSource: DisplayNameSource? = nil,
        instrumentType: InstrumentType? = nil,
        addedAt: Date = .now,
        lots: [CostLot] = [],
        transactions: [PositionTransaction] = []
    ) {
        self.symbol = symbol
        self.displayName = displayName
        self.displayNameSource = displayNameSource
        self.instrumentType = Self.normalizedInstrumentType(instrumentType, for: symbol)
        self.addedAt = addedAt
        self.lots = lots
        self.transactions = transactions
    }

    enum CodingKeys: String, CodingKey {
        case symbol, displayName, displayNameSource, instrumentType, addedAt, lots, transactions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(SymbolID.self, forKey: .symbol)
        displayName = try container.decode(String.self, forKey: .displayName)
        displayNameSource = try container.decodeIfPresent(DisplayNameSource.self, forKey: .displayNameSource)
        instrumentType = try container.decodeIfPresent(InstrumentType.self, forKey: .instrumentType)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        lots = try container.decodeIfPresent([CostLot].self, forKey: .lots) ?? []
        transactions = try container.decodeIfPresent([PositionTransaction].self, forKey: .transactions) ?? []
    }

    public var id: SymbolID { symbol }

    /// The persisted name is the user-facing identity chosen when the symbol was
    /// added. Quote providers must not replace it as routing or failover changes.
    /// Indices use Pulse's localized catalog so every provider presents one name.
    public var resolvedDisplayName: String {
        if let index = symbol.indexID { return index.displayName }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? symbol.displayCode : displayName
    }

    public var resolvedInstrumentType: InstrumentType? {
        Self.normalizedInstrumentType(instrumentType, for: symbol)
    }

    /// An index is a calculated benchmark rather than a directly held security.
    /// ETFs and other exchange-traded products remain position-eligible.
    public var supportsPosition: Bool {
        resolvedInstrumentType != .index
    }

    static func normalizedInstrumentType(
        _ instrumentType: InstrumentType?,
        for symbol: SymbolID
    ) -> InstrumentType? {
        if symbol.indexID != nil { return .index }
        if symbol.cryptoPair != nil { return .crypto }
        return instrumentType
    }

    /// Replayed ledger when the item has transaction history.
    public var ledger: PositionLedger? {
        transactions.isEmpty ? nil : PositionLedger(transactions: transactions)
    }

    public var positionQuantity: Double {
        if let ledger { return ledger.quantity }
        return lots.reduce(0) { $0 + $1.quantity }
    }

    public var costBasis: Double {
        if let ledger { return ledger.costBasis }
        return lots.reduce(0) { $0 + $1.price * $1.quantity }
    }

    public var averageCost: Double? {
        if let ledger { return ledger.hasOpenPosition ? ledger.averageCost : nil }
        let quantity = positionQuantity
        guard quantity > 0 else { return nil }
        return costBasis / quantity
    }

    /// Cumulative realized P&L; survives a flat position. Zero for legacy
    /// lot-only items that never recorded a transaction.
    public var realizedPnL: Double {
        ledger?.realizedPnL ?? 0
    }

    public var hasPosition: Bool {
        positionQuantity > 0 && averageCost != nil
    }

    /// Whether the item carries any position data worth showing: an open
    /// position or transaction history (realized P&L survives selling out).
    public var hasPositionHistory: Bool {
        hasPosition || !transactions.isEmpty
    }

    /// Legacy lots materialized as an opening adjustment, so recording the
    /// first real trade on a lot-based item folds the existing position into
    /// the ledger instead of dropping it. Multiple lots collapse into their
    /// combined quantity and average cost — exactly what the ledger derives.
    public func materializedTransactions() -> [PositionTransaction] {
        guard transactions.isEmpty else { return transactions }
        let quantity = lots.reduce(0) { $0 + $1.quantity }
        guard quantity > 0 else { return [] }
        let costBasis = lots.reduce(0) { $0 + $1.price * $1.quantity }
        let date = lots.compactMap(\.date).min() ?? addedAt
        return [PositionTransaction(
            kind: .adjustment,
            price: costBasis / quantity,
            quantity: quantity,
            date: date,
            createdAt: date
        )]
    }
}

public struct PositionMetrics: Sendable, Hashable {
    public var quantity: Double
    public var averageCost: Double
    public var costBasis: Double
    public var marketValue: Double
    public var totalPnL: Double
    public var totalReturnPercent: Double
    public var todayPnL: Double
    public var todayReturnPercent: Double

    public init?(item: WatchItem, quote: Quote) {
        guard item.supportsPosition else { return nil }
        let quantity = item.positionQuantity
        guard quantity > 0, let averageCost = item.averageCost else { return nil }

        let costBasis = item.costBasis
        let marketValue = quote.price * quantity
        let totalPnL = marketValue - costBasis
        let todayPnL = quote.change * quantity

        self.quantity = quantity
        self.averageCost = averageCost
        self.costBasis = costBasis
        self.marketValue = marketValue
        self.totalPnL = totalPnL
        self.totalReturnPercent = costBasis == 0 ? 0 : totalPnL / costBasis * 100
        self.todayPnL = todayPnL
        self.todayReturnPercent = quote.previousClose == 0 ? 0 : quote.change / quote.previousClose * 100
    }
}
