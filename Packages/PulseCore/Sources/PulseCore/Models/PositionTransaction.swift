import Foundation

/// A single position-changing event. The transaction list is the source of
/// truth for a holding; the current quantity, moving-average cost, and
/// realized P&L are all replayed from it (see `PositionLedger`).
public struct PositionTransaction: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case buy
        case sell
        /// Overwrites the position with a target quantity and average cost
        /// ("I don't want to itemize — here is the result"). Produces no
        /// realized P&L. Quick-set edits and legacy cost lots land here.
        case adjustment
    }

    public var id: UUID
    public var kind: Kind
    /// Trade price per unit; for `.adjustment` the target average cost.
    public var price: Double
    /// Traded quantity; for `.adjustment` the target total quantity.
    public var quantity: Double
    /// User-facing trade date (day granularity).
    public var date: Date
    /// Insertion timestamp; breaks replay-order ties between same-day entries.
    public var createdAt: Date
    /// Reserved for V1.5 (no UI yet).
    public var fee: Double?
    public var note: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        price: Double,
        quantity: Double,
        date: Date = .now,
        createdAt: Date = .now,
        fee: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.price = price
        self.quantity = quantity
        self.date = date
        self.createdAt = createdAt
        self.fee = fee
        self.note = note
    }
}

/// Replays a transaction list into the current position using the
/// moving-weighted-average cost method: buys blend into the average cost,
/// sells realize (price − average cost) × quantity and leave the remaining
/// units' average cost unchanged.
public struct PositionLedger: Sendable, Hashable {
    /// A transaction annotated with its replay outcome, in replay order.
    public struct Entry: Sendable, Hashable, Identifiable {
        public var transaction: PositionTransaction
        /// P&L realized by this entry (sells only).
        public var realizedPnL: Double?
        public var resultingQuantity: Double
        public var resultingAverageCost: Double

        public var id: UUID { transaction.id }
    }

    public var entries: [Entry]
    public var quantity: Double
    /// Moving-weighted-average cost of the currently held units.
    public var averageCost: Double
    /// Cost basis of the currently held units (quantity × average cost).
    public var costBasis: Double
    /// Cumulative realized P&L across all sells, surviving a flat position.
    public var realizedPnL: Double

    public init(transactions: [PositionTransaction]) {
        var entries: [Entry] = []
        var quantity = 0.0
        var averageCost = 0.0
        var realizedPnL = 0.0

        for transaction in Self.replayOrdered(transactions) {
            var entryRealized: Double?
            switch transaction.kind {
            case .buy:
                let bought = max(transaction.quantity, 0)
                let newQuantity = quantity + bought
                if newQuantity > 0 {
                    averageCost = (averageCost * quantity + transaction.price * bought) / newQuantity
                }
                quantity = newQuantity
            case .sell:
                // A backdated entry can momentarily exceed what was held at
                // that point in the replay; sell what exists and never go short.
                let sold = min(max(transaction.quantity, 0), quantity)
                let realized = (transaction.price - averageCost) * sold
                realizedPnL += realized
                entryRealized = realized
                quantity -= sold
                if quantity <= 0 {
                    quantity = 0
                    averageCost = 0
                }
            case .adjustment:
                quantity = max(transaction.quantity, 0)
                averageCost = quantity > 0 ? max(transaction.price, 0) : 0
            }
            entries.append(Entry(
                transaction: transaction,
                realizedPnL: entryRealized,
                resultingQuantity: quantity,
                resultingAverageCost: averageCost
            ))
        }

        self.entries = entries
        self.quantity = quantity
        self.averageCost = averageCost
        self.costBasis = averageCost * quantity
        self.realizedPnL = realizedPnL
    }

    public var hasOpenPosition: Bool { quantity > 0 }

    /// Chronological replay order: trade date first, insertion order breaking
    /// same-day ties so re-sorting never shuffles what the user entered.
    public static func replayOrdered(_ transactions: [PositionTransaction]) -> [PositionTransaction] {
        transactions.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
