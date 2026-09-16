import Foundation

/// Buy/sell transactions grouped onto one daily candle. Transactions only carry a
/// user-facing calendar date, so these markers deliberately have no intraday form.
public struct CandleTradeMarker: Sendable, Hashable, Identifiable {
    public enum Side: String, Sendable, Hashable {
        case buy
        case sell
    }

    public struct ID: Sendable, Hashable {
        public var candleTime: Date
        public var side: Side

        public init(candleTime: Date, side: Side) {
            self.candleTime = candleTime
            self.side = side
        }
    }

    public var id: ID
    public var candleIndex: Int
    public var candleTime: Date
    public var side: Side
    public var averagePrice: Double
    public var totalQuantity: Double
    public var totalAmount: Double
    public var transactions: [PositionTransaction]

    public var count: Int { transactions.count }

    /// Matches the date the user picked to the exchange-local date of each daily
    /// candle. The two calendars are intentionally separate: a US trade entered on
    /// August 11 from China is still the August 11 US trading day, even though the
    /// stored start-of-day instant falls on August 10 in New York.
    ///
    /// A trade dated on a day with no candle — a weekend or holiday, or the local
    /// calendar day a late-session fill fell on — snaps to the nearest candle day
    /// rather than vanishing. The snap is bounded so a misdated entry from far
    /// outside the loaded history still stays off the chart.
    public static func dailyMarkers(
        candles: [Candle],
        transactions: [PositionTransaction],
        market: Market?,
        transactionCalendar: Calendar = .current
    ) -> [CandleTradeMarker] {
        guard !candles.isEmpty, !transactions.isEmpty else { return [] }
        let dayIndex = CandleDayIndex(
            candles: candles,
            market: market,
            fallbackTimeZone: transactionCalendar.timeZone
        )

        struct GroupKey: Hashable {
            var candleIndex: Int
            var side: Side
        }

        var grouped: [GroupKey: [PositionTransaction]] = [:]
        for transaction in transactions {
            let side: Side
            switch transaction.kind {
            case .buy: side = .buy
            case .sell: side = .sell
            case .adjustment: continue
            }
            guard transaction.price.isFinite, transaction.quantity.isFinite,
                  transaction.price > 0, transaction.quantity > 0 else {
                continue
            }
            let day = Day(transaction.date, calendar: transactionCalendar)
            guard let candleIndex = dayIndex.candleIndex(for: day) else {
                continue
            }
            grouped[GroupKey(candleIndex: candleIndex, side: side), default: []].append(transaction)
        }

        return grouped.compactMap { key, values in
            let ordered = PositionLedger.replayOrdered(values)
            let totalQuantity = ordered.reduce(0) { $0 + $1.quantity }
            let totalAmount = ordered.reduce(0) { $0 + $1.price * $1.quantity }
            guard totalQuantity.isFinite, totalQuantity > 0,
                  totalAmount.isFinite,
                  candles.indices.contains(key.candleIndex) else { return nil }
            let candle = candles[key.candleIndex]
            return CandleTradeMarker(
                id: ID(candleTime: candle.time, side: key.side),
                candleIndex: key.candleIndex,
                candleTime: candle.time,
                side: key.side,
                averagePrice: totalAmount / totalQuantity,
                totalQuantity: totalQuantity,
                totalAmount: totalAmount,
                transactions: ordered
            )
        }
        .sorted {
            if $0.candleIndex != $1.candleIndex { return $0.candleIndex < $1.candleIndex }
            return $0.side == .buy && $1.side == .sell
        }
    }

    /// Where a transaction dated `date` would land on the daily chart, resolved
    /// exactly the way `dailyMarkers` resolves it. Entry/edit forms use this to
    /// tell the user what a non-trading-day date means before they save; the
    /// recorded date itself is never rewritten.
    public enum MarkerDay: Sendable, Equatable {
        /// The market traded that day; the marker sits on the day's own candle.
        case tradingDay(Date)
        /// The day falls inside the loaded history with no candle of its own —
        /// a weekend or holiday — so the marker snaps to `candleDay`.
        case closedDay(candleDay: Date)
        /// The day lies outside the loaded history: today's bar may not be
        /// published yet (or the cache predates it), the date may be in the
        /// future, or older than the history reaches. The candles can't say
        /// whether the market traded, so nothing should call the day closed.
        /// The chart still snaps to the nearest bar when one is close enough
        /// (`candleDay`) and drops the marker otherwise.
        case outsideHistory(candleDay: Date?)
    }

    public static func markerDay(
        for date: Date,
        candles: [Candle],
        market: Market?,
        transactionCalendar: Calendar = .current
    ) -> MarkerDay {
        guard !candles.isEmpty else { return .outsideHistory(candleDay: nil) }
        let dayIndex = CandleDayIndex(
            candles: candles,
            market: market,
            fallbackTimeZone: transactionCalendar.timeZone
        )
        let day = Day(date, calendar: transactionCalendar)
        if let index = dayIndex.indexByDay[day] {
            return .tradingDay(candles[index].time)
        }
        let nearest = dayIndex.candleIndex(for: day).map { candles[$0].time }
        guard let first = dayIndex.sortedDays.first?.day,
              let last = dayIndex.sortedDays.last?.day,
              day.ordinal > first.ordinal, day.ordinal < last.ordinal,
              let candleDay = nearest else {
            return .outsideHistory(candleDay: nearest)
        }
        return .closedDay(candleDay: candleDay)
    }

    /// The furthest a non-trading-day trade may sit from the candle it snaps to.
    /// Covers weekends and week-long exchange closures (Golden Week, New Year);
    /// anything farther away is treated as a misdated entry and stays off.
    private static let maxSnapDayDistance = 7

    /// Closest candle day to `day`, nearest first and the earlier day on a tie,
    /// or nil when every candle lies outside `maxSnapDayDistance`.
    private static func nearestCandleIndex(
        to day: Day,
        in sortedDays: [(day: Day, index: Int)]
    ) -> Int? {
        var best: (distance: Int, index: Int)?
        for entry in sortedDays {
            let distance = abs(entry.day.ordinal - day.ordinal)
            guard distance <= maxSnapDayDistance,
                  distance < (best?.distance ?? .max) else { continue }
            best = (distance, entry.index)
        }
        return best?.index
    }

    /// Exact-day lookup plus nearest-day fallback shared by `dailyMarkers` and
    /// `markerDay`, so a form's "where the marker lands" answer can never drift
    /// from what the chart actually draws.
    private struct CandleDayIndex {
        var indexByDay: [Day: Int] = [:]
        var sortedDays: [(day: Day, index: Int)] = []

        init(candles: [Candle], market: Market?, fallbackTimeZone: TimeZone) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = market?.timeZone ?? fallbackTimeZone
            for (index, candle) in candles.enumerated() {
                indexByDay[Day(candle.time, calendar: calendar)] = index
            }
            sortedDays = indexByDay
                .map { (day: $0.key, index: $0.value) }
                .sorted { $0.day.ordinal < $1.day.ordinal }
        }

        func candleIndex(for day: Day) -> Int? {
            indexByDay[day] ?? CandleTradeMarker.nearestCandleIndex(to: day, in: sortedDays)
        }
    }
}

private struct Day: Hashable {
    var era: Int
    var year: Int
    var month: Int
    var day: Int

    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        era = components.era ?? 0
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    /// Proleptic Gregorian day number (days-from-civil), so days produced by
    /// different calendars can be compared by distance alone.
    var ordinal: Int {
        // 1 BC reads back as era 0 / year 1; astronomical numbering makes it 0.
        var y = era == 0 ? 1 - year : year
        y -= month <= 2 ? 1 : 0
        let e = (y >= 0 ? y : y - 399) / 400
        let yoe = y - e * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yoe * 365 + yoe / 4 - yoe / 100 + dayOfYear
        return e * 146097 + dayOfEra
    }
}
