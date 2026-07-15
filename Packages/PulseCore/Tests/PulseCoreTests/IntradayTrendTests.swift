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
        #expect(IntradayTrendSnapshot.recommendedCandleCount(for: .us) == 400)
        #expect(IntradayTrendSnapshot.recommendedCandleCount(for: .crypto) == 1_440)
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
