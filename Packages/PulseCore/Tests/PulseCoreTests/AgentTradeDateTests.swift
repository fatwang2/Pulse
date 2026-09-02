import Foundation
import Testing
@testable import PulseCore

@Suite("Agent trade dates")
struct AgentTradeDateTests {
    private func instant(_ string: String) throws -> Date {
        try Date(string, strategy: Date.ISO8601FormatStyle())
    }

    @Test("A bare day maps to local midnight")
    func bareDay() throws {
        let calendar = Calendar.current
        let parsed = try #require(AgentTradeDate.parse("2026-09-02", calendar: calendar))
        #expect(parsed == calendar.date(from: DateComponents(year: 2026, month: 9, day: 2)))
        #expect(calendar.startOfDay(for: parsed) == parsed)
    }

    @Test("A bare day follows the calendar's zone, not UTC")
    func bareDayInAnotherZone() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let parsed = try #require(AgentTradeDate.parse("2026-09-02", calendar: tokyo))
        #expect(parsed == (try instant("2026-09-01T15:00:00Z")))
    }

    @Test("A date-time keeps the instant it names")
    func dateTime() throws {
        let expected = try instant("2026-09-02T14:30:00Z")
        #expect(AgentTradeDate.parse("2026-09-02T14:30:00Z") == expected)
        #expect(AgentTradeDate.parse("2026-09-02T22:30:00+08:00") == expected)
        #expect(AgentTradeDate.parse("2026-09-02T14:30:00.250Z") == expected.addingTimeInterval(0.25))
    }

    @Test("Anything else is rejected rather than guessed", arguments: [
        "", "today", "2026-9-2", "20260902", "2026-09-02xyz", "2026-02-30",
        "2026-09-02T14:30:00", "２０２６-09-02",
    ])
    func rejects(_ string: String) {
        #expect(AgentTradeDate.parse(string) == nil)
    }
}
