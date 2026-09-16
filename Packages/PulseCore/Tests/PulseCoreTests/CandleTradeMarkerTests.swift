import Foundation
import Testing
@testable import PulseCore

@Suite("Daily candle trade markers")
struct CandleTradeMarkerTests {
    @Test("User calendar date maps to the same exchange trading day")
    func crossTimeZoneDateMapping() throws {
        var entryCalendar = Calendar(identifier: .gregorian)
        entryCalendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var marketCalendar = Calendar(identifier: .gregorian)
        marketCalendar.timeZone = Market.us.timeZone

        let transactionDate = try #require(entryCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 11
        )))
        let candleDate = try #require(marketCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 11, hour: 9, minute: 30
        )))
        let candle = Candle(time: candleDate, open: 100, high: 105, low: 99, close: 104)
        let transaction = PositionTransaction(
            kind: .buy,
            price: 102,
            quantity: 5,
            date: transactionDate
        )

        let markers = CandleTradeMarker.dailyMarkers(
            candles: [candle],
            transactions: [transaction],
            market: .us,
            transactionCalendar: entryCalendar
        )

        let marker = try #require(markers.first)
        #expect(markers.count == 1)
        #expect(marker.candleIndex == 0)
        #expect(marker.side == .buy)
        #expect(marker.averagePrice == 102)
    }

    @Test("Same-day trades aggregate by side at weighted average price")
    func aggregatesBySide() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Hong_Kong"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))
        let candles = [Candle(time: date, open: 100, high: 130, low: 90, close: 120)]
        let transactions = [
            PositionTransaction(kind: .buy, price: 100, quantity: 10, date: date),
            PositionTransaction(kind: .buy, price: 120, quantity: 30, date: date),
            PositionTransaction(kind: .sell, price: 125, quantity: 5, date: date),
            PositionTransaction(kind: .adjustment, price: 110, quantity: 20, date: date),
        ]

        let markers = CandleTradeMarker.dailyMarkers(
            candles: candles,
            transactions: transactions,
            market: .hk,
            transactionCalendar: calendar
        )

        let buy = try #require(markers.first { $0.side == .buy })
        let sell = try #require(markers.first { $0.side == .sell })
        #expect(markers.count == 2)
        #expect(buy.count == 2)
        #expect(buy.totalQuantity == 40)
        #expect(buy.totalAmount == 4_600)
        #expect(buy.averagePrice == 115)
        #expect(sell.count == 1)
        #expect(sell.averagePrice == 125)
    }

    @Test("A weekend trade snaps to the nearest candle day")
    func weekendTradeSnapsToNearestTradingDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.us.timeZone
        let friday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14)))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 17)))
        let saturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 16)))
        let candles = [
            Candle(time: friday, open: 100, high: 101, low: 99, close: 100),
            Candle(time: monday, open: 100, high: 101, low: 99, close: 100),
        ]
        let transactions = [
            PositionTransaction(kind: .sell, price: 100, quantity: 1, date: saturday),
            PositionTransaction(kind: .buy, price: 100, quantity: 1, date: sunday),
        ]

        let markers = CandleTradeMarker.dailyMarkers(
            candles: candles,
            transactions: transactions,
            market: .us,
            transactionCalendar: calendar
        )

        // Saturday sits one day off Friday and two off Monday; Sunday mirrors it.
        let saturdaySell = try #require(markers.first { $0.side == .sell })
        let sundayBuy = try #require(markers.first { $0.side == .buy })
        #expect(saturdaySell.candleIndex == 0)
        #expect(sundayBuy.candleIndex == 1)
    }

    @Test("markerDay reports the landing candle and whether the day is a closure")
    func markerDayReportsSnap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.us.timeZone
        let friday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14)))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 17)))
        let saturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        let monthEarlier = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
        let candles = [
            Candle(time: friday, open: 100, high: 101, low: 99, close: 100),
            Candle(time: monday, open: 100, high: 101, low: 99, close: 100),
        ]

        #expect(CandleTradeMarker.markerDay(
            for: friday, candles: candles, market: .us, transactionCalendar: calendar
        ) == .tradingDay(friday))
        #expect(CandleTradeMarker.markerDay(
            for: saturday, candles: candles, market: .us, transactionCalendar: calendar
        ) == .closedDay(candleDay: friday))
        #expect(CandleTradeMarker.markerDay(
            for: monthEarlier, candles: candles, market: .us, transactionCalendar: calendar
        ) == .outsideHistory(candleDay: nil))
        #expect(CandleTradeMarker.markerDay(
            for: saturday, candles: [], market: .us, transactionCalendar: calendar
        ) == .outsideHistory(candleDay: nil))
    }

    @Test("A day past the last loaded candle is never reported closed")
    func dayBeyondHistoryIsNotAClosure() throws {
        // A trade entered mid-session: the day's bar isn't published yet (or
        // the cache predates it), so the loaded history ends the day before.
        // The chart still snaps to that last bar, but the day must not read
        // as a market closure.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.us.timeZone
        let tuesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16)))
        let thursday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let candles = [
            Candle(time: tuesday, open: 100, high: 101, low: 99, close: 100),
            Candle(time: wednesday, open: 100, high: 101, low: 99, close: 100),
        ]

        #expect(CandleTradeMarker.markerDay(
            for: thursday, candles: candles, market: .us, transactionCalendar: calendar
        ) == .outsideHistory(candleDay: wednesday))

        // The same instant seen from a calendar a day ahead of New York (a
        // fill recorded from China after local midnight, during the US
        // session) resolves identically: the local label is already
        // "tomorrow" relative to the live bar.
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let localThursday = try #require(shanghai.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        #expect(CandleTradeMarker.markerDay(
            for: localThursday, candles: candles, market: .us, transactionCalendar: shanghai
        ) == .outsideHistory(candleDay: wednesday))

        // A day before the first bar is equally unknowable.
        let lastFriday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11)))
        #expect(CandleTradeMarker.markerDay(
            for: lastFriday, candles: candles, market: .us, transactionCalendar: calendar
        ) == .outsideHistory(candleDay: tuesday))
    }

    @Test("Transactions far outside the loaded candles stay off the chart")
    func distantDateIsIgnored() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.us.timeZone
        let friday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14)))
        let monthEarlier = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
        let candle = Candle(time: friday, open: 100, high: 101, low: 99, close: 100)
        let transaction = PositionTransaction(kind: .sell, price: 100, quantity: 1, date: monthEarlier)

        let markers = CandleTradeMarker.dailyMarkers(
            candles: [candle],
            transactions: [transaction],
            market: .us,
            transactionCalendar: calendar
        )

        #expect(markers.isEmpty)
    }

    @Test("Non-finite transactions never produce chart markers")
    func nonFiniteValuesAreIgnored() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.us.timeZone
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))
        let candle = Candle(time: date, open: 100, high: 101, low: 99, close: 100)
        let transactions = [
            PositionTransaction(kind: .buy, price: .infinity, quantity: 1, date: date),
            PositionTransaction(kind: .sell, price: 100, quantity: .infinity, date: date),
            PositionTransaction(kind: .buy, price: .nan, quantity: 1, date: date),
        ]

        let markers = CandleTradeMarker.dailyMarkers(
            candles: [candle],
            transactions: transactions,
            market: .us,
            transactionCalendar: calendar
        )

        #expect(markers.isEmpty)
    }
}
