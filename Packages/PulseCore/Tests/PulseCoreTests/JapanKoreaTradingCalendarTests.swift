import Foundation
import Testing
@testable import PulseCore

/// 2026-08-17 is a Monday, so the 17th–21st are weekdays and the 22nd a Saturday.
private func date(_ market: Market, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = market.timeZone
    return try #require(calendar.date(
        from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute)
    ))
}

@Suite("Tokyo trading session")
struct TokyoTradingCalendarTests {
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try date(.jp, day, hour, minute)
    }

    @Test("The day is split by a one-hour lunch break")
    func lunchBreak() throws {
        #expect(TradingCalendar.state(of: .jp, at: try at(19, 8, 59)) == .closed)
        #expect(TradingCalendar.state(of: .jp, at: try at(19, 9)) == .regular)
        #expect(TradingCalendar.state(of: .jp, at: try at(19, 11, 29)) == .regular)
        #expect(TradingCalendar.state(of: .jp, at: try at(19, 11, 30)) == .lunchBreak)
        #expect(TradingCalendar.state(of: .jp, at: try at(19, 12, 29)) == .lunchBreak)
        #expect(TradingCalendar.state(of: .jp, at: try at(19, 12, 30)) == .regular)
    }

    /// Tokyo moved its close from 15:00 to 15:30 in November 2024.
    @Test("The afternoon runs to 15:30")
    func afternoonClose() throws {
        #expect(TradingCalendar.state(of: .jp, at: try at(19, 15)) == .regular)
        #expect(TradingCalendar.state(of: .jp, at: try at(19, 15, 29)) == .regular)
        #expect(TradingCalendar.state(of: .jp, at: try at(19, 15, 30)) == .closed)
    }

    @Test("Weekends have no session")
    func weekend() throws {
        #expect(TradingCalendar.state(of: .jp, at: try at(22, 10)) == .closed)
        #expect(TradingCalendar.state(of: .jp, at: try at(23, 10)) == .closed)
    }

    @Test("The intraday axis collapses the lunch gap")
    func intradayAxis() throws {
        let session = IntradayTradingSession(market: .jp, referenceDate: try at(19, 13))
        #expect(session.morningMinutes == 150)   // 09:00–11:30
        #expect(session.totalMinutes == 330)     // plus 12:30–15:30
        // 12:30 resumes exactly where 11:30 stopped, so the break costs no width.
        #expect(session.minuteOffset(for: try at(19, 11, 30)) == 150)
        #expect(session.minuteOffset(for: try at(19, 12, 30)) == 150)
        #expect(session.minuteOffset(for: try at(19, 15, 30)) == 330)
    }
}

@Suite("Seoul trading session")
struct SeoulTradingCalendarTests {
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try date(.kr, day, hour, minute)
    }

    /// Seoul is the one Asian market in Pulse that trades straight through midday.
    @Test("The session is continuous, closing auction included")
    func continuousSession() throws {
        #expect(TradingCalendar.state(of: .kr, at: try at(19, 8, 59)) == .closed)
        #expect(TradingCalendar.state(of: .kr, at: try at(19, 9)) == .regular)
        #expect(TradingCalendar.state(of: .kr, at: try at(19, 12)) == .regular)
        #expect(TradingCalendar.state(of: .kr, at: try at(19, 15, 29)) == .regular)
        #expect(TradingCalendar.state(of: .kr, at: try at(19, 15, 30)) == .closed)
    }

    @Test("Both boards keep the same hours")
    func boardsAgree() throws {
        for hour in [9, 12, 15] {
            #expect(
                TradingCalendar.state(of: .kq, at: try at(19, hour))
                    == TradingCalendar.state(of: .kr, at: try at(19, hour))
            )
        }
        #expect(TradingCalendar.state(of: .kq, at: try at(22, 10)) == .closed)
    }

    @Test("The intraday axis has no gap to collapse")
    func intradayAxis() throws {
        let session = IntradayTradingSession(market: .kr, referenceDate: try at(19, 13))
        #expect(session.morningEnd == nil)
        #expect(session.afternoonStart == nil)
        #expect(session.totalMinutes == 390)     // 09:00–15:30 unbroken
        #expect(session.minuteOffset(for: try at(19, 12, 15)) == 195)
    }
}

@Suite("Japan and Korea market metadata")
struct JapanKoreaMarketTests {
    @Test("Currency and time zone follow the exchange")
    func currencyAndZone() {
        #expect(Market.jp.currencyCode == "JPY")
        #expect(Market.kr.currencyCode == "KRW")
        #expect(Market.kq.currencyCode == "KRW")
        #expect(Market.jp.timeZone.identifier == "Asia/Tokyo")
        #expect(Market.kr.timeZone.identifier == "Asia/Seoul")
        #expect(Market.kq.timeZone.identifier == "Asia/Seoul")
        #expect(Market.kr.isKorea && Market.kq.isKorea)
        #expect(!Market.jp.isKorea)
    }

    /// KOSPI and KOSDAQ are one market to the reader; only the symbol says which.
    @Test("Both Korean boards share a label and a watchlist block")
    func koreanBoardsPresentAsOne() {
        #expect(Market.kr.displayName == Market.kq.displayName)
        #expect(MarketBlock(market: .kr) == .korea)
        #expect(MarketBlock(market: .kq) == .korea)
        #expect(MarketBlock(market: .jp) == .jp)
    }

    @Test("Both schedule windows place Japan and Korea after China A")
    func blockOrder() throws {
        for window in [MarketScheduleWindow.asiaDay, .usEvening] {
            let order = window.blockOrder
            let china = try #require(order.firstIndex(of: .chinaA))
            let japan = try #require(order.firstIndex(of: .jp))
            let korea = try #require(order.firstIndex(of: .korea))
            let metal = try #require(order.firstIndex(of: .metal))
            #expect(china < japan)
            #expect(japan < korea)
            // Metals and crypto stay last whatever the window.
            #expect(korea < metal)
            #expect(order.count == MarketBlock.allCases.count)
        }
    }

    @Test("The headline indices resolve to one identity per market")
    func indexIdentities() {
        #expect(MarketIndexID.nikkei225.market == .jp)
        #expect(MarketIndexID.kospi.market == .kr)
        #expect(MarketIndexID.resolve(market: .jp, code: "^N225") == .nikkei225)
        #expect(MarketIndexID.resolve(market: .jp, code: "N225.T") == .nikkei225)
        #expect(MarketIndexID.resolve(market: .kr, code: "^KS11") == .kospi)
        #expect(MarketIndexID.resolve(market: .kq, code: "KOSPI") == .kospi)
        #expect(MarketIndexID.resolve(market: .jp, code: "7203") == nil)
    }
}
