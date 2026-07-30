#if os(macOS)
import Foundation
import Testing
@testable import PulseCore

@Suite("Longbridge US minute candle backfill")
struct LongbridgeMinuteCandleBackfillTests {
    @Test("Backfills when a full latest page starts inside the visible session")
    func detectsTruncatedPremarket() throws {
        let calendar = Self.exchangeCalendar(.us)
        let day = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 29))
        )
        var candles: [Candle] = []
        for offset in 0..<1_000 {
            let seconds = TimeInterval((8 * 60 + 2 + offset) * 60)
            candles.append(Self.candle(
                at: day.addingTimeInterval(seconds),
                close: Double(offset)
            ))
        }

        #expect(
            LongbridgeMinuteCandleBackfill.needsOlderPage(
                candles,
                market: .us,
                period: .minute1,
                latestPageReachedLimit: true
            )
        )
    }

    @Test("Backfills when pre-market rows crowd out the prior regular session")
    func detectsPriorRegularSessionCutDuringPremarket() throws {
        // 08:29 ET during pre-market: the 1,000-row "All sessions" page reaches back
        // through today's pre (270) + overnight (480) + yesterday's post (240) and keeps
        // only the last ~10 minutes of yesterday's regular session — the very session
        // the regular-mode sparkline still anchors on.
        let calendar = Self.exchangeCalendar(.us)
        let today = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 29))
        )
        let end = today.addingTimeInterval(TimeInterval((8 * 60 + 29) * 60))
        let candles = (0..<1_000).map { offset in
            Self.candle(
                at: end.addingTimeInterval(TimeInterval(-60 * offset)),
                close: Double(offset)
            )
        }

        #expect(
            LongbridgeMinuteCandleBackfill.needsOlderPage(
                candles,
                market: .us,
                period: .minute1,
                latestPageReachedLimit: true
            )
        )
    }

    @Test("Does not backfill when the oldest row is still overnight")
    func skipsCompleteVisibleSession() throws {
        let calendar = Self.exchangeCalendar(.us)
        let day = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 29))
        )
        var candles: [Candle] = []
        for offset in 0..<1_000 {
            let seconds = TimeInterval((2 * 60 + offset) * 60)
            candles.append(Self.candle(
                at: day.addingTimeInterval(seconds),
                close: Double(offset)
            ))
        }

        #expect(
            !LongbridgeMinuteCandleBackfill.needsOlderPage(
                candles,
                market: .us,
                period: .minute1,
                latestPageReachedLimit: true
            )
        )
    }

    @Test("Merge sorts, deduplicates, and prefers the latest page")
    func mergesPages() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let older = [
            Self.candle(at: base, close: 1),
            Self.candle(at: base.addingTimeInterval(60), close: 2),
        ]
        let latest = [
            Self.candle(at: base.addingTimeInterval(60), close: 20),
            Self.candle(at: base.addingTimeInterval(120), close: 3),
        ]

        let merged = LongbridgeMinuteCandleBackfill.merge(
            older: older,
            latest: latest,
            limit: 10
        )

        #expect(merged.map(\.time) == [
            base,
            base.addingTimeInterval(60),
            base.addingTimeInterval(120),
        ])
        #expect(merged.map(\.close) == [1, 20, 3])
    }

    private static func exchangeCalendar(_ market: Market) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        return calendar
    }

    private static func candle(at time: Date, close: Double) -> Candle {
        Candle(
            time: time,
            open: close,
            high: close,
            low: close,
            close: close,
            volume: 1
        )
    }
}
#endif
