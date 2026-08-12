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

    @Test("Transactions without a matching trading day stay off the chart")
    func unmatchedDateIsIgnored() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.us.timeZone
        let friday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14)))
        let saturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        let candle = Candle(time: friday, open: 100, high: 101, low: 99, close: 100)
        let transaction = PositionTransaction(kind: .sell, price: 100, quantity: 1, date: saturday)

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
