import Foundation

/// What a position was measured from at the start of the session the current
/// quote is showing, replayed from the transaction list.
///
/// Day P&L is the change in what a position is worth since the previous close,
/// net of what was put in or taken out during the session. Shares held through
/// the previous close are measured from `previousClose`; shares traded today
/// are measured from their trade price, which is the whole point — a lot bought
/// this morning never earned the move that preceded it.
public struct PositionDayBasis: Sendable, Hashable {
    /// Signed quantity held at the previous close: the only shares whose day
    /// baseline is `previousClose`.
    public var openingQuantity: Double
    /// Net cash today's trades put into the position (buys positive, sells
    /// negative). Subtracting it from the market value leaves today's move.
    public var netInvestedToday: Double
    /// Signed quantity from trades the quote's session predates. Nothing has
    /// marked them yet, so they drop out of the day entirely.
    public var unmarkedQuantity: Double
    /// The capital today's result is measured against: the previous close value
    /// of the opening position plus the cost of exposure opened during the
    /// session. Zero when there is nothing to measure.
    public var costBase: Double

    /// Where a single trade sits relative to the quote's session.
    enum Cohort {
        /// Settled before the session: measured from the previous close.
        case opening
        /// Traded during the session: measured from its own trade price.
        case today
        /// Dated past the session the quote belongs to, with no session running
        /// to place it in — no price has marked it yet.
        case unmarked
    }

    public init(
        openingQuantity: Double = 0,
        netInvestedToday: Double = 0,
        unmarkedQuantity: Double = 0,
        costBase: Double = 0
    ) {
        self.openingQuantity = openingQuantity
        self.netInvestedToday = netInvestedToday
        self.unmarkedQuantity = unmarkedQuantity
        self.costBase = costBase
    }

    public init(item: WatchItem, quote: Quote, now: Date = .now) {
        guard let ledger = item.ledger else {
            // Legacy lot-only items carry no trade dates worth trusting; the
            // whole position counts as held through the previous close, which
            // is how it has always been measured.
            let quantity = item.positionQuantity
            self.init(
                openingQuantity: quantity,
                costBase: abs(quote.previousClose * quantity)
            )
            return
        }

        let sessionDay = TradingCalendar.tradingDay(of: item.symbol.market, at: quote.timestamp)
        // A session in progress means any trade the user dated "today" belongs
        // to it, even when the local date and the exchange's have drifted apart
        // (a US session spans midnight in Asia, and an Asian session spans it
        // the other way).
        let liveSession = TradingCalendar.state(of: item.symbol.market, at: now) != .closed
        let localToday = CalendarDay(now, in: .current)

        var openingQuantity = 0.0
        var netInvestedToday = 0.0
        var unmarkedQuantity = 0.0
        var openedTodayCost = 0.0
        var runningQuantity = 0.0

        for entry in ledger.entries {
            let transaction = entry.transaction
            switch transaction.kind {
            case .adjustment:
                // A calibration states the position as it stands rather than
                // trading it, and supersedes everything before it — today's
                // trades included. Its price is an average cost, not a fill, so
                // it cannot say anything about the session and the position
                // reverts to being measured from the previous close.
                openingQuantity = entry.resultingQuantity
                netInvestedToday = 0
                unmarkedQuantity = 0
                openedTodayCost = 0
            case .buy, .sell:
                let traded = max(transaction.quantity, 0)
                let signed = transaction.kind == .buy ? traded : -traded
                switch Self.cohort(
                    of: transaction,
                    market: item.symbol.market,
                    sessionDay: sessionDay,
                    localToday: localToday,
                    liveSession: liveSession
                ) {
                case .opening:
                    openingQuantity += signed
                case .today:
                    netInvestedToday += signed * transaction.price
                    // Only the part that opens or extends exposure funds the
                    // day: a same-day round trip is measured against what was
                    // bought, not against buy plus sell.
                    let opened = abs(entry.resultingQuantity) - abs(runningQuantity)
                    openedTodayCost += max(0, opened) * transaction.price
                case .unmarked:
                    unmarkedQuantity += signed
                }
            }
            runningQuantity = entry.resultingQuantity
        }

        self.init(
            openingQuantity: openingQuantity,
            netInvestedToday: netInvestedToday,
            unmarkedQuantity: unmarkedQuantity,
            costBase: abs(quote.previousClose * openingQuantity) + openedTodayCost
        )
    }

    /// Trade dates are day-granular and entered in the user's own calendar, so
    /// they are compared as calendar days against the session's, never as
    /// instants. The insertion timestamp settles what the date alone cannot:
    /// a trade entered before this session opened belongs to an earlier one,
    /// however the user dated it.
    private static func cohort(
        of transaction: PositionTransaction,
        market: Market,
        sessionDay: CalendarDay,
        localToday: CalendarDay,
        liveSession: Bool
    ) -> Cohort {
        // Recorded before this session opened, so whatever day the user picked,
        // the position was already standing when the session began. This is how
        // a US trade a user in Asia dated with their local today — a date the
        // exchange has yet to reach — settles down once that session ends.
        if TradingCalendar.tradingDay(of: market, at: transaction.createdAt) < sessionDay { return .opening }

        let tradeDay = CalendarDay(transaction.date, in: .current)
        // A session in progress claims anything the user dated today, however
        // far the two calendars have drifted apart in either direction.
        if liveSession, tradeDay == localToday { return .today }
        if tradeDay < sessionDay { return .opening }
        if tradeDay == sessionDay { return .today }
        // Dated past the session the quote belongs to: while a session runs the
        // local date has simply run ahead of the exchange's, but with the market
        // closed no price has marked the trade yet.
        return liveSession ? .today : .unmarked
    }
}
