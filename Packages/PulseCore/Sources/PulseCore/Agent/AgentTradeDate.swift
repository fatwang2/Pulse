import Foundation

/// The `date` an agent sends with a trade or calibration.
///
/// Trade dates are calendar days in the user's own time zone, so the
/// canonical form is a bare `YYYY-MM-DD`, which maps to that day's local
/// midnight — the same instant the app's own entry form records. A full
/// ISO 8601 date-time (with or without fractional seconds) is accepted as
/// well and kept as the instant it names; the ledger files it under the local
/// day it falls on, exactly as the app displays it. Anything else is rejected
/// rather than guessed at, so a malformed date never lands as "today".
public enum AgentTradeDate {
    public static func parse(_ string: String, calendar: Calendar = .current) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if let instant = (try? Date(trimmed, strategy: plainStyle))
            ?? (try? Date(trimmed, strategy: fractionalStyle)) {
            return instant
        }
        guard let components = bareDayComponents(trimmed),
              let date = calendar.date(from: DateComponents(
                  year: components.year, month: components.month, day: components.day
              )) else {
            return nil
        }
        // `date(from:)` rolls an impossible day forward (February 30 becomes
        // March 2); only a date that reads back unchanged names a real day.
        let parsed = calendar.dateComponents([.year, .month, .day], from: date)
        guard parsed.year == components.year,
              parsed.month == components.month,
              parsed.day == components.day else {
            return nil
        }
        return date
    }

    /// Exactly `YYYY-MM-DD` in ASCII digits. Foundation's day-only ISO 8601
    /// style is lenient about trailing characters and separators, so the
    /// shape is checked by hand instead.
    private static func bareDayComponents(_ string: String) -> (year: Int, month: Int, day: Int)? {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return (year, month, day)
    }

    private static let plainStyle = Date.ISO8601FormatStyle()
    private static let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
