import Foundation

/// A single position-changing event. The transaction list is the source of
/// truth for a holding; the current quantity, moving-average cost, and
/// realized P&L are all replayed from it (see `PositionLedger`).
public struct PositionTransaction: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case buy
        case sell
        /// Overwrites the position with a target quantity and average cost
        /// ("I don't want to itemize — here is the result"). A negative
        /// target quantity calibrates a short. Produces no realized P&L.
        /// Quick-set edits and legacy cost lots land here.
        case adjustment
    }

    public var id: UUID
    public var kind: Kind
    /// Trade price per unit; for `.adjustment` the target average cost.
    public var price: Double
    /// Traded quantity; for `.adjustment` the target total quantity.
    public var quantity: Double
    /// User-facing trade date. Read as a calendar day in the user's own time
    /// zone everywhere (replay order, day P&L, chart markers, agent readback):
    /// the entry form records local midnight, a quick-set calibration keeps
    /// the time it was made, and an agent may send any instant — none of
    /// which may change which day the trade lands on or how it orders
    /// against other trades that day.
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
/// moving-weighted-average cost method. Quantity is signed: positive is a
/// long, negative a short (opened by selling first). On the long side buys
/// blend into the average cost and sells realize (price − average cost) ×
/// quantity; on the short side the roles mirror — sells blend into the
/// average short price and buys cover, realizing (average cost − price) ×
/// quantity. A trade crossing zero closes the open side first, then opens
/// the opposite side at the trade price with the remainder.
public struct PositionLedger: Sendable, Hashable {
    /// A transaction annotated with its replay outcome, in replay order.
    public struct Entry: Sendable, Hashable, Identifiable {
        public var transaction: PositionTransaction
        /// P&L realized by this entry (sells closing a long, buys covering
        /// a short).
        public var realizedPnL: Double?
        public var resultingQuantity: Double
        public var resultingAverageCost: Double

        public var id: UUID { transaction.id }
    }

    public var entries: [Entry]
    /// Signed: positive units held long, negative units sold short.
    public var quantity: Double
    /// Moving-weighted-average entry price of the open side (long cost or
    /// short sale price); always non-negative.
    public var averageCost: Double
    /// Cost basis of the open position (quantity × average cost); negative
    /// for a short, where it represents the short-sale proceeds.
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
                if quantity >= 0 {
                    let newQuantity = quantity + bought
                    if newQuantity > 0 {
                        averageCost = (averageCost * quantity + transaction.price * bought) / newQuantity
                    }
                    quantity = newQuantity
                } else {
                    // Buying against a short covers first, realizing
                    // (average short price − buy price) × covered; anything
                    // past flat flips into a long opened at the trade price.
                    let covered = min(bought, -quantity)
                    let realized = (averageCost - transaction.price) * covered
                    realizedPnL += realized
                    entryRealized = realized
                    quantity += bought
                    if quantity > 0 {
                        averageCost = transaction.price
                    } else if quantity == 0 {
                        averageCost = 0
                    }
                }
            case .sell:
                let sold = max(transaction.quantity, 0)
                if quantity > 0 {
                    // Selling closes the long first, realizing (price −
                    // average cost) × closed; anything past flat flips into
                    // a short opened at the trade price.
                    let closed = min(sold, quantity)
                    let realized = (transaction.price - averageCost) * closed
                    realizedPnL += realized
                    entryRealized = realized
                    quantity -= sold
                    if quantity < 0 {
                        averageCost = transaction.price
                    } else if quantity == 0 {
                        averageCost = 0
                    }
                } else {
                    // Selling while flat or short opens/extends the short;
                    // the average blends the short entry prices.
                    let short = -quantity + sold
                    if short > 0 {
                        averageCost = (averageCost * -quantity + transaction.price * sold) / short
                    }
                    quantity = -short
                }
            case .adjustment:
                quantity = transaction.quantity
                averageCost = quantity != 0 ? max(transaction.price, 0) : 0
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

    public var hasOpenPosition: Bool { quantity != 0 }

    /// Chronological replay order: trade day first, insertion order breaking
    /// same-day ties so re-sorting never shuffles what the user entered.
    ///
    /// The trade date is compared as a calendar day in the user's zone, never
    /// as an instant. Same-day entries carry different times of day — the
    /// entry form dates trades at local midnight while a quick-set calibration
    /// keeps the time it was made — and comparing instants replayed a buy
    /// dated "today" ahead of a calibration made that morning, letting the
    /// calibration wipe it out.
    ///
    /// Two trades recorded back to back share both timestamps about three times
    /// in four — `Date.now` is not fine-grained enough to separate consecutive
    /// calls — so the final tie-break decides the order far more often than it
    /// looks. It has to be the position in the stored array, which is the order
    /// the user entered them in; ordering by `id` there sorted random UUIDs and
    /// shuffled the ledger roughly half the time it was consulted.
    public static func replayOrdered(
        _ transactions: [PositionTransaction],
        timeZone: TimeZone = .current
    ) -> [PositionTransaction] {
        transactions.enumerated()
            .map { offset, transaction in
                (day: CalendarDay(transaction.date, in: timeZone), transaction: transaction, offset: offset)
            }
            .sorted { lhs, rhs in
                if lhs.day != rhs.day {
                    return lhs.day < rhs.day
                }
                if lhs.transaction.createdAt != rhs.transaction.createdAt {
                    return lhs.transaction.createdAt < rhs.transaction.createdAt
                }
                return lhs.offset < rhs.offset
            }
            .map(\.transaction)
    }
}
