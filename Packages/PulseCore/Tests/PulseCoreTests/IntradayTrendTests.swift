import Foundation
import Testing
@testable import PulseCore

@Suite("Canonical intraday trend")
struct IntradayTrendTests {
    @Test("Keeps only the latest exchange session and sorts it")
    func latestSessionFiltering() throws {
        let calendar = exchangeCalendar(.sh)
        let latestDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
        let priorDay = try #require(calendar.date(byAdding: .day, value: -1, to: latestDay))
        let candles = [
            candle(at: priorDay.addingTimeInterval(14 * 3600), close: 90),
            candle(at: latestDay.addingTimeInterval(13 * 3600 + 5 * 60), close: 102),
            candle(at: latestDay.addingTimeInterval(9 * 3600 + 31 * 60), close: 100),
            candle(at: latestDay.addingTimeInterval(8 * 3600), close: 99),
        ]

        let trend = IntradayTrendSnapshot(candles: candles, market: .sh)

        #expect(trend.candles.map(\.close) == [100, 102])
        #expect(trend.session.minuteOffset(for: trend.candles[0].time) == 1)
        #expect(trend.session.minuteOffset(for: trend.candles[1].time) == 125)
        #expect(trend.session.totalMinutes == 240)
    }

    @Test("Uses one full day of minute data for every market")
    func recommendedCounts() {
        #expect(IntradayTrendSnapshot.recommendedCandleCount(for: .sh) == 400)
        // Longbridge pages the US request as 1,000 recent + up to 600 older rows.
        #expect(IntradayTrendSnapshot.recommendedCandleCount(for: .us) == 1_600)
        #expect(IntradayTrendSnapshot.recommendedCandleCount(for: .crypto) == 1_440)
        // A metal session is 23 hours plus room for the closing bar.
        #expect(IntradayTrendSnapshot.recommendedCandleCount(for: .metal) == 1_400)
    }

    @Test("A metal chart spans one session, 18:00 ET to 17:00 ET")
    func metalSessionFrame() throws {
        let calendar = exchangeCalendar(.metal)
        let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 19)))

        // Morning in New York: the session under way opened the evening before.
        let morning = IntradayTradingSession(
            market: .metal,
            referenceDate: wednesday.addingTimeInterval(9 * 3600)
        )
        #expect(calendar.dateComponents([.day, .hour], from: morning.open) == DateComponents(day: 18, hour: 18))
        #expect(calendar.dateComponents([.day, .hour], from: morning.close) == DateComponents(day: 19, hour: 17))
        #expect(morning.totalMinutes == 23 * 60)
        #expect(morning.morningEnd == nil)
        // 09:00 ET is fifteen hours into a session that opened at 18:00.
        #expect(morning.minuteOffset(for: wednesday.addingTimeInterval(9 * 3600)) == 15 * 60)

        // Past 18:00 the next session has already started.
        let evening = IntradayTradingSession(
            market: .metal,
            referenceDate: wednesday.addingTimeInterval(19 * 3600)
        )
        #expect(calendar.dateComponents([.day, .hour], from: evening.open) == DateComponents(day: 19, hour: 18))
    }

    /// London spot is only quoted from the session open, so its line has to start
    /// at the left edge; the older bars Yahoo returns for the COMEX contract
    /// belong to the previous session and are trimmed by the same frame.
    @Test("A metal trend keeps the session on screen, not the calendar day")
    func metalTrendKeepsSession() throws {
        let calendar = exchangeCalendar(.metal)
        let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 19)))
        let tuesday = try #require(calendar.date(byAdding: .day, value: -1, to: wednesday))
        let candles = [
            candle(at: wednesday.addingTimeInterval(10 * 3600), close: 90),    // previous session
            candle(at: wednesday.addingTimeInterval(18 * 3600), close: 100),   // session open
            candle(at: wednesday.addingTimeInterval(22 * 3600), close: 101),   // New York evening
            candle(at: tuesday.addingTimeInterval(48 * 3600 + 3 * 3600), close: 102),  // Thu 03:00, small hours
        ]

        let trend = IntradayTrendSnapshot(candles: candles, market: .metal)

        #expect(trend.candles.map(\.close) == [100, 101, 102])
        // The session open sits at the very left of the axis.
        #expect(trend.session.minuteOffset(for: trend.candles[0].time) == 0)
        #expect(trend.session.minuteOffset(for: trend.candles[1].time) == 4 * 60)
        #expect(trend.session.minuteOffset(for: trend.candles[2].time) == 9 * 60)
    }

    @Test("Extended-hours wings compress onto 15% of the plot each")
    func extendedWingGeometry() throws {
        let calendar = exchangeCalendar(.us)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 29)))
        let session = IntradayTradingSession(market: .us, referenceDate: day, includesExtendedHours: true)

        let wing = 390.0 * 3 / 14
        #expect(session.totalMinutes == 390)
        #expect(abs(session.axisLowerBound + wing) < 0.001)
        #expect(abs(session.axisUpperBound - (390 + wing)) < 0.001)

        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        // Pre wing: 4:00 → left edge, 9:30 → 0; regular unchanged; post wing: 16:00 → 390, 20:00 → right edge
        #expect(abs(session.minuteOffset(for: at(4, 0)) - session.axisLowerBound) < 0.001)
        #expect(abs(session.minuteOffset(for: at(6, 45)) - session.axisLowerBound / 2) < 0.001)
        #expect(session.minuteOffset(for: at(9, 30)) == 0)
        #expect(session.minuteOffset(for: at(12, 0)) == 150)
        #expect(session.minuteOffset(for: at(16, 0)) == 390)
        #expect(abs(session.minuteOffset(for: at(18, 0)) - (390 + wing / 2)) < 0.001)
        #expect(abs(session.minuteOffset(for: at(20, 0)) - session.axisUpperBound) < 0.001)

        // date(forMinute:) inverts the wing mapping
        #expect(session.date(forMinute: session.axisLowerBound) == at(4, 0))
        #expect(session.date(forMinute: session.axisUpperBound) == at(20, 0))
        #expect(session.date(forMinute: 390 + wing / 2) == at(18, 0))

        #expect(session.sessionKind(for: at(5, 0)) == .pre)
        #expect(session.sessionKind(for: at(10, 0)) == .regular)
        #expect(session.sessionKind(for: at(17, 0)) == .post)

        // Overnight bars sit outside the extended frame and get filtered out
        #expect(!session.contains(at(21, 0)))
        #expect(!session.contains(at(3, 0)))
        #expect(session.contains(at(4, 30)))
        #expect(session.contains(at(19, 59)))
    }

    @Test("Regular sessions are unaffected by the extended flag on non-US markets")
    func extendedFlagIgnoredOutsideUS() throws {
        let calendar = exchangeCalendar(.hk)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 29)))
        let extended = IntradayTradingSession(market: .hk, referenceDate: day, includesExtendedHours: true)
        let regular = IntradayTradingSession(market: .hk, referenceDate: day)
        #expect(extended == regular)
        #expect(!extended.includesExtendedHours)
    }

    @Test("A pre-market-only morning anchors the regular chart on the prior session")
    func preMarketMorningKeepsPriorRegularSession() throws {
        let calendar = exchangeCalendar(.us)
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 29)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let candles = [
            candle(at: yesterday.addingTimeInterval(10 * 3600), close: 100),      // yesterday 10:00 regular
            candle(at: yesterday.addingTimeInterval(15 * 3600 + 59 * 60), close: 101),
            candle(at: yesterday.addingTimeInterval(17 * 3600), close: 102),      // yesterday 17:00 post
            candle(at: today.addingTimeInterval(5 * 3600), close: 103),           // today 5:00 pre
        ]

        // Regular mode skips pre/post bars and keeps showing yesterday's session
        let regular = IntradayTrendSnapshot(candles: candles, market: .us)
        #expect(regular.candles.map(\.close) == [100, 101])

        // Extended mode frames today, so the growing pre-market line is what's shown
        let extended = IntradayTrendSnapshot(candles: candles, market: .us, includesExtendedHours: true)
        #expect(extended.candles.map(\.close) == [103])
        #expect(extended.session.sessionKind(for: extended.candles[0].time) == .pre)
    }

    @Test("Extended snapshot keeps pre, regular and post bars of the same day")
    func extendedSnapshotSpansAllSessions() throws {
        let calendar = exchangeCalendar(.us)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 29)))
        let candles = [
            candle(at: day.addingTimeInterval(5 * 3600), close: 99),              // pre
            candle(at: day.addingTimeInterval(10 * 3600), close: 100),            // regular
            candle(at: day.addingTimeInterval(17 * 3600), close: 101),            // post
            candle(at: day.addingTimeInterval(21 * 3600), close: 102),            // overnight — dropped
        ]
        let trend = IntradayTrendSnapshot(candles: candles, market: .us, includesExtendedHours: true)
        #expect(trend.candles.map(\.close) == [99, 100, 101])
    }

    @Test("Historical US minute K filtering follows the chart session preference")
    func historicalSessionFiltering() throws {
        let calendar = exchangeCalendar(.us)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 29)))
        let candles = [
            candle(at: day.addingTimeInterval(3 * 3600), close: 98),              // overnight
            candle(at: day.addingTimeInterval(5 * 3600), close: 99),              // pre
            candle(at: day.addingTimeInterval(10 * 3600), close: 100),            // regular
            candle(at: day.addingTimeInterval(17 * 3600), close: 101),            // post
            candle(at: day.addingTimeInterval(21 * 3600), close: 102),            // overnight
        ]

        let regular = IntradayTradingSession.filterCandles(
            candles, market: .us, includesExtendedHours: false
        )
        #expect(regular.map(\.close) == [100])

        let extended = IntradayTradingSession.filterCandles(
            candles, market: .us, includesExtendedHours: true
        )
        #expect(extended.map(\.close) == [99, 100, 101])
        #expect(IntradayTradingSession.usSessionKind(for: extended[0].time) == .pre)
        #expect(IntradayTradingSession.usSessionKind(for: extended[1].time) == .regular)
        #expect(IntradayTradingSession.usSessionKind(for: extended[2].time) == .post)
    }

    private func exchangeCalendar(_ market: Market) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        return calendar
    }

    private func candle(at time: Date, close: Double) -> Candle {
        Candle(time: time, open: close, high: close, low: close, close: close)
    }
}
