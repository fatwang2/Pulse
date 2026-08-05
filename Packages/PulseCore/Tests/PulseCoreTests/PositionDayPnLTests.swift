import Foundation
import Testing
@testable import PulseCore

/// Day P&L measures shares held through the previous close from that close,
/// and shares traded during the session from their trade price.
@Suite("Position day P&L")
struct PositionDayPnLTests {
    private let symbol = SymbolID(market: .us, code: "AAPL")

    private func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? .distantPast
    }

    /// Monday 10:00 ET: a live regular session, so the quote's day is 06-16.
    private var sessionMoment: Date { instant("2025-06-16T14:00:00Z") }
    private var today: Date { instant("2025-06-16T12:00:00Z") }
    private var lastWeek: Date { instant("2025-06-12T12:00:00Z") }

    private func item(_ transactions: [PositionTransaction]) -> WatchItem {
        WatchItem(symbol: symbol, displayName: "Apple", transactions: transactions)
    }

    private func quote(price: Double, previousClose: Double, at timestamp: Date? = nil) -> Quote {
        Quote(
            symbol: symbol,
            price: price,
            previousClose: previousClose,
            timestamp: timestamp ?? sessionMoment
        )
    }

    @Test("A position opened today is measured from its trade price, not the previous close")
    func openedToday() throws {
        let item = item([PositionTransaction(kind: .buy, price: 200, quantity: 100, date: today)])
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190),
            now: sessionMoment
        ))
        // Bought at 200 and now 210: the 190 → 200 move happened before the
        // position existed and is not the holder's.
        #expect(metrics.todayPnL == 1_000)
        #expect(abs(metrics.todayReturnPercent - 5) < 0.001)
        #expect(metrics.totalPnL == 1_000)
    }

    @Test("A position held through the previous close is still measured from it")
    func heldThroughClose() throws {
        let item = item([PositionTransaction(kind: .buy, price: 200, quantity: 100, date: lastWeek)])
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190),
            now: sessionMoment
        ))
        #expect(metrics.todayPnL == 2_000)
        #expect(abs(metrics.todayReturnPercent - 10.5263) < 0.001)
    }

    @Test("Adding to a position today splits the day between both baselines")
    func addedToday() throws {
        let item = item([
            PositionTransaction(kind: .buy, price: 180, quantity: 100, date: lastWeek),
            PositionTransaction(kind: .buy, price: 205, quantity: 50, date: today),
        ])
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190),
            now: sessionMoment
        ))
        // 100 shares from 190 → 210, plus 50 shares from 205 → 210.
        #expect(metrics.todayPnL == 2_250)
        // Measured against the previous close value plus today's purchase.
        #expect(abs(metrics.todayReturnPercent - 7.6923) < 0.001)
    }

    @Test("Selling today keeps the day P&L the sale realized")
    func soldToday() throws {
        let item = item([
            PositionTransaction(kind: .buy, price: 180, quantity: 100, date: lastWeek),
            PositionTransaction(kind: .sell, price: 205, quantity: 40, date: today),
        ])
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190),
            now: sessionMoment
        ))
        // 60 shares still held from 190 → 210, plus 40 sold from 190 → 205.
        #expect(metrics.todayPnL == 1_800)
        #expect(abs(metrics.todayReturnPercent - 9.4736) < 0.001)
    }

    @Test("A same-day round trip is measured against what it bought")
    func roundTripToday() {
        let item = item([
            PositionTransaction(kind: .buy, price: 200, quantity: 100, date: today),
            PositionTransaction(kind: .sell, price: 205, quantity: 100, date: today),
        ])
        let quote = quote(price: 210, previousClose: 190)
        let basis = PositionDayBasis(item: item, quote: quote, now: sessionMoment)
        #expect(basis.openingQuantity == 0)
        #expect(basis.netInvestedToday == -500)
        // The sell closes exposure rather than funding more of it.
        #expect(basis.costBase == 20_000)
    }

    @Test("Calibrating a holding today does not turn total P&L into today's")
    func calibrationIsNotATrade() throws {
        // Quick set records an average cost, not a fill: a long-held position
        // entered into Pulse today still has its day measured from the close.
        let item = item([PositionTransaction(kind: .adjustment, price: 50, quantity: 100, date: today)])
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190),
            now: sessionMoment
        ))
        #expect(metrics.todayPnL == 2_000)
        #expect(metrics.totalPnL == 16_000)
    }

    @Test("A calibration supersedes the trades it follows")
    func calibrationSupersedesTodaysTrades() throws {
        let item = item([
            PositionTransaction(kind: .buy, price: 200, quantity: 100, date: today, createdAt: today),
            PositionTransaction(
                kind: .adjustment,
                price: 200,
                quantity: 100,
                date: today,
                createdAt: today.addingTimeInterval(60)
            ),
        ])
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190),
            now: sessionMoment
        ))
        #expect(metrics.todayPnL == 2_000)
    }

    @Test("A short opened today is measured from its sale price")
    func shortOpenedToday() throws {
        let item = item([PositionTransaction(kind: .sell, price: 200, quantity: 100, date: today)])
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 195, previousClose: 190),
            now: sessionMoment
        ))
        // Shorted at 200 and now 195: a gain, even though the symbol is up on
        // the day.
        #expect(metrics.todayPnL == 500)
        #expect(abs(metrics.todayReturnPercent - 2.5) < 0.001)
    }

    @Test("A trade dated ahead of the session still counts while that session runs")
    func localDateAheadOfTheExchange() throws {
        // A US session spans midnight in Asia, so "today" for the user can be
        // the day after the session's own date.
        let tomorrow = instant("2025-06-17T12:00:00Z")
        let item = item([PositionTransaction(kind: .buy, price: 200, quantity: 100, date: tomorrow)])
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190, at: instant("2025-06-16T18:00:00Z")),
            now: instant("2025-06-16T18:00:00Z")
        ))
        #expect(metrics.todayPnL == 1_000)
    }

    @Test("A trade recorded in an earlier session is held through its close")
    func recordedBeforeThisSession() throws {
        // Entered 14:00 ET Monday and dated with a local calendar already on
        // Tuesday. Once Tuesday's session opens, those shares have been held
        // through Monday's close and are measured from it.
        let item = item([PositionTransaction(
            kind: .buy,
            price: 200,
            quantity: 100,
            date: instant("2025-06-17T12:00:00Z"),
            createdAt: instant("2025-06-16T18:00:00Z")
        )])
        let tuesday = instant("2025-06-17T14:00:00Z")
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190, at: tuesday),
            now: tuesday
        ))
        #expect(metrics.todayPnL == 2_000)
    }

    @Test("A trade no session has marked yet contributes nothing to the day")
    func recordedWhileClosed() throws {
        // Friday's close is the last mark; a trade recorded on Saturday has not
        // traded against any price the quote knows.
        let fridayClose = instant("2025-06-13T20:00:00Z")
        let saturday = instant("2025-06-14T12:00:00Z")
        let item = item([PositionTransaction(kind: .buy, price: 200, quantity: 100, date: saturday)])
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190, at: fridayClose),
            now: instant("2025-06-14T18:00:00Z")
        ))
        #expect(metrics.todayPnL == 0)
        #expect(metrics.todayReturnPercent == 0)
        // The position itself is still worth what it is worth.
        #expect(metrics.totalPnL == 1_000)
    }

    @Test("Legacy lot-only positions keep their previous-close baseline")
    func legacyLots() throws {
        var item = WatchItem(symbol: symbol, displayName: "Apple")
        item.lots = [CostLot(price: 200, quantity: 10, date: today)]
        let metrics = try #require(PositionMetrics(
            item: item,
            quote: quote(price: 210, previousClose: 190),
            now: sessionMoment
        ))
        #expect(metrics.todayPnL == 200)
    }

    @Test("The trading day of a US overnight session is the session that follows it")
    func overnightTradingDay() {
        // 21:00 ET Monday belongs to Tuesday's session.
        let monday = instant("2025-06-17T01:00:00Z")
        #expect(TradingCalendar.tradingDay(of: .us, at: monday) == CalendarDay(year: 2025, month: 6, day: 17))
        // The small hours already carry the session's own date.
        let earlyTuesday = instant("2025-06-17T06:00:00Z")
        #expect(TradingCalendar.tradingDay(of: .us, at: earlyTuesday) == CalendarDay(year: 2025, month: 6, day: 17))
    }
}
