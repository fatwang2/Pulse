import Foundation
import Testing
@testable import PulseCore

/// Metals are the first market whose session runs through the night and pauses
/// for an hour a day, so its boundaries get their own coverage.
@Suite("Metal trading session")
struct MetalTradingCalendarTests {
    private func newYork(_ components: DateComponents) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.metal.timeZone
        return try #require(calendar.date(from: components))
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try newYork(DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))
    }

    // 2026-08-16 is a Sunday; the week therefore runs 17th (Mon) to 21st (Fri).
    @Test("Sunday evening opens the week")
    func sundayOpen() throws {
        #expect(TradingCalendar.state(of: .metal, at: try at(16, 12)) == .closed)
        #expect(TradingCalendar.state(of: .metal, at: try at(16, 17, 59)) == .closed)
        #expect(TradingCalendar.state(of: .metal, at: try at(16, 18)) == .regular)
        #expect(TradingCalendar.state(of: .metal, at: try at(16, 23)) == .regular)
    }

    @Test("Weekdays pause only for the settlement hour")
    func weekdayBreak() throws {
        #expect(TradingCalendar.state(of: .metal, at: try at(19, 3)) == .regular)
        #expect(TradingCalendar.state(of: .metal, at: try at(19, 10)) == .regular)
        #expect(TradingCalendar.state(of: .metal, at: try at(19, 16, 59)) == .regular)
        #expect(TradingCalendar.state(of: .metal, at: try at(19, 17)) == .closed)
        #expect(TradingCalendar.state(of: .metal, at: try at(19, 17, 59)) == .closed)
        #expect(TradingCalendar.state(of: .metal, at: try at(19, 18)) == .regular)
    }

    @Test("Friday 17:00 closes the week and Saturday stays shut")
    func weekendClose() throws {
        #expect(TradingCalendar.state(of: .metal, at: try at(21, 16, 59)) == .regular)
        #expect(TradingCalendar.state(of: .metal, at: try at(21, 17)) == .closed)
        #expect(TradingCalendar.state(of: .metal, at: try at(21, 20)) == .closed)
        #expect(TradingCalendar.state(of: .metal, at: try at(22, 10)) == .closed)
    }

    @Test("Refreshing follows the session, including overnight")
    func refreshWindow() throws {
        #expect(TradingCalendar.isActive(.metal, at: try at(19, 2)))
        #expect(TradingCalendar.isActive(.metal, at: try at(19, 20)))
        #expect(!TradingCalendar.isActive(.metal, at: try at(19, 17, 30)))
        #expect(!TradingCalendar.isActive(.metal, at: try at(22, 10)))
    }

    /// Both sources report metals by exchange calendar day, so a bar from the
    /// evening reopen still belongs to the New York date it printed on.
    @Test("Metal bars keep their exchange calendar day")
    func tradingDayAttribution() throws {
        #expect(
            TradingCalendar.tradingDay(of: .metal, at: try at(19, 20))
                == CalendarDay(year: 2026, month: 8, day: 19)
        )
        #expect(
            TradingCalendar.tradingDay(of: .metal, at: try at(19, 10))
                == CalendarDay(year: 2026, month: 8, day: 19)
        )
    }
}


/// Shanghai metals are the first market with a night leg that opens the trading
/// day, so its boundaries get their own coverage.
@Suite("Shanghai metal trading session")
struct ShanghaiMetalCalendarTests {
    private func beijing(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.metalCN.timeZone
        return try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute)
        ))
    }

    // 2026-08-16 is a Sunday; the week runs 17th (Mon) to 21st (Fri).
    @Test("The day session keeps its lunch break")
    func daySession() throws {
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(19, 8, 59)) == .closed)
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(19, 9)) == .regular)
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(19, 11, 30)) == .lunchBreak)
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(19, 13, 30)) == .regular)
        // The Gold Exchange settles at 15:30, half an hour after the futures one.
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(19, 15, 15)) == .regular)
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(19, 15, 30)) == .closed)
    }

    @Test("The night leg runs 21:00 into the small hours")
    func nightSession() throws {
        // The Gold Exchange opens its night leg at 20:00, an hour before futures.
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(19, 19, 59)) == .closed)
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(19, 20)) == .regular)
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(19, 21)) == .regular)
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(20, 2, 29)) == .regular)
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(20, 2, 30)) == .closed)
    }

    @Test("Only nights that follow a trading day exist")
    func weekEdges() throws {
        // Friday night runs into Saturday; Sunday night does not exist, so Monday
        // opens at 09:00 rather than in the small hours.
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(22, 1)) == .regular)   // Sat, from Fri night
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(22, 10)) == .closed)   // Sat daytime
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(23, 21)) == .closed)   // Sun night
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(17, 1)) == .closed)    // Mon small hours
        #expect(TradingCalendar.state(of: .metalCN, at: try beijing(21, 22)) == .regular)  // Fri night
    }

    @Test("A Shanghai chart day opens with the night session")
    func sessionFrame() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.metalCN.timeZone
        let session = IntradayTradingSession(market: .metalCN, referenceDate: try beijing(20, 10))

        #expect(calendar.dateComponents([.day, .hour], from: session.open)
            == DateComponents(day: 19, hour: 20))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: session.close)
            == DateComponents(day: 20, hour: 15, minute: 30))
        // The 02:30–09:00 gap collapses the way an A-share lunch break does.
        #expect(session.morningMinutes == 390)
        #expect(session.totalMinutes == 780)
        #expect(session.minuteOffset(for: try beijing(20, 9, 1)) == 391)

        // Past 20:00 the next trading day has already started.
        let evening = IntradayTradingSession(market: .metalCN, referenceDate: try beijing(20, 22))
        #expect(calendar.dateComponents([.day, .hour], from: evening.open)
            == DateComponents(day: 20, hour: 20))
    }
}
