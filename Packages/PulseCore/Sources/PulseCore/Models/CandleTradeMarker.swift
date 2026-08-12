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
    public static func dailyMarkers(
        candles: [Candle],
        transactions: [PositionTransaction],
        market: Market?,
        transactionCalendar: Calendar = .current
    ) -> [CandleTradeMarker] {
        guard !candles.isEmpty, !transactions.isEmpty else { return [] }

        var candleCalendar = Calendar(identifier: .gregorian)
        candleCalendar.timeZone = market?.timeZone ?? transactionCalendar.timeZone

        var candleIndexByDay: [Day: Int] = [:]
        for (index, candle) in candles.enumerated() {
            candleIndexByDay[Day(candle.time, calendar: candleCalendar)] = index
        }

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
                  transaction.price > 0, transaction.quantity > 0,
                  let candleIndex = candleIndexByDay[Day(transaction.date, calendar: transactionCalendar)] else {
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
}
