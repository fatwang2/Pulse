import Foundation

/// One exchange trading day expressed in trading minutes. Lunch breaks collapse to a
/// single x-axis boundary so every surface can position intraday points identically.
public struct IntradayTradingSession: Sendable, Hashable {
    public let open: Date
    public let morningEnd: Date?
    public let afternoonStart: Date?
    public let close: Date

    public init(market: Market, referenceDate: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        let day = calendar.startOfDay(for: referenceDate)
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        switch market {
        case .sh, .sz:
            open = at(9, 30)
            morningEnd = at(11, 30)
            afternoonStart = at(13, 0)
            close = at(15, 0)
        case .hk:
            open = at(9, 30)
            morningEnd = at(12, 0)
            afternoonStart = at(13, 0)
            close = at(16, 0)
        case .us:
            open = at(9, 30)
            morningEnd = nil
            afternoonStart = nil
            close = at(16, 0)
        case .crypto:
            open = at(0, 0)
            morningEnd = nil
            afternoonStart = nil
            close = at(23, 59)
        }
    }

    public var morningMinutes: Double {
        (morningEnd ?? close).timeIntervalSince(open) / 60
    }

    public var totalMinutes: Double {
        guard let afternoonStart else { return morningMinutes }
        return morningMinutes + close.timeIntervalSince(afternoonStart) / 60
    }

    /// Includes a one-minute tolerance for providers that timestamp the opening/closing bucket edge.
    public func contains(_ date: Date) -> Bool {
        date >= open.addingTimeInterval(-60) && date <= close.addingTimeInterval(60)
    }

    /// Wall-clock date → trading-minute offset; lunch collapses onto the morning close.
    public func minuteOffset(for date: Date) -> Double {
        if date <= open { return 0 }
        if let morningEnd, let afternoonStart {
            if date <= morningEnd { return date.timeIntervalSince(open) / 60 }
            if date < afternoonStart { return morningMinutes }
            return min(morningMinutes + date.timeIntervalSince(afternoonStart) / 60, totalMinutes)
        }
        return min(date.timeIntervalSince(open) / 60, totalMinutes)
    }

    /// Trading-minute offset → wall-clock date, using the afternoon side of the lunch boundary.
    public func date(forMinute minute: Double) -> Date {
        if let afternoonStart, minute > morningMinutes {
            return afternoonStart.addingTimeInterval((minute - morningMinutes) * 60)
        }
        return open.addingTimeInterval(minute * 60)
    }
}

/// Canonical current-session series shared by the list, detail chart, and share cards.
public struct IntradayTrendSnapshot: Sendable, Hashable {
    public let session: IntradayTradingSession
    public let candles: [Candle]

    public init(candles: [Candle], market: Market) {
        let referenceDate = candles.max(by: { $0.time < $1.time })?.time ?? .now
        let session = IntradayTradingSession(market: market, referenceDate: referenceDate)
        self.session = session
        self.candles = candles
            .filter { session.contains($0.time) }
            .sorted { $0.time < $1.time }
    }

    public static func recommendedCandleCount(for market: Market) -> Int {
        market == .crypto ? 24 * 60 : 400
    }
}
