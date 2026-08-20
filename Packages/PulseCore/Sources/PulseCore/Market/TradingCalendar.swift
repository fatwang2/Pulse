import Foundation

public enum SessionState: String, Sendable {
    case closed, preMarket, regular, lunchBreak, postMarket
    /// US overnight session (Sun 20:00 ET through Fri 04:00 ET, in nightly slices)
    case overnight
}

/// Trading sessions per market (in each exchange's time zone).
/// TODO: holiday calendar (Chinese New Year / National Day / Thanksgiving, etc.); the MVP uses a simple Monday-to-Friday rule.
/// Japan makes this the most visible gap: about twenty public holidays plus the
/// 12/31–1/3 exchange closure means roughly six weeks of weekdays a year are
/// reported open when Tokyo is shut.
public enum TradingCalendar {
    public static func state(of market: Market, at date: Date = .now) -> SessionState {
        if market == .crypto { return .regular }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = comps.weekday, let hour = comps.hour, let minute = comps.minute else {
            return .closed
        }
        let m = hour * 60 + minute

        // Metals run almost continuously: Sun 18:00 ET through Fri 17:00 ET, pausing
        // one hour a day for settlement. Like the US overnight session, that reaches
        // outside the Monday–Friday rule below.
        if market == .metal {
            if weekday == 1 { return m >= 18 * 60 ? .regular : .closed }  // Sunday evening opens the week
            guard (2...6).contains(weekday) else { return .closed }       // Saturday has no session
            if m < 17 * 60 { return .regular }
            if weekday == 6 { return .closed }                            // Friday 17:00 closes the week
            return m >= 18 * 60 ? .regular : .closed                      // 17:00–18:00 settlement break
        }

        // Shanghai metals trade a night leg ahead of the day session, so like the
        // US overnight it reaches outside the Monday–Friday rule below. The two
        // exchanges differ slightly — the Gold Exchange opens at 20:00 and settles
        // at 15:30, the Futures Exchange at 21:00 and 15:00 — so the window is
        // their union: an instrument simply has no bars in the part it misses.
        if market == .metalCN {
            if m >= 20 * 60 { return (2...6).contains(weekday) ? .regular : .closed }
            // The small hours belong to the previous evening's session: Saturday
            // has one because Friday night ran into it, Monday does not.
            if m < 2 * 60 + 30 { return (3...7).contains(weekday) ? .regular : .closed }
            guard (2...6).contains(weekday) else { return .closed }
            if (9 * 60)..<(11 * 60 + 30) ~= m { return .regular }
            if (11 * 60 + 30)..<(13 * 60 + 30) ~= m { return .lunchBreak }
            if (13 * 60 + 30)..<(15 * 60 + 30) ~= m { return .regular }
            return .closed
        }

        // The US overnight session runs Sun 20:00 ET through Fri 04:00 ET, so it is the one
        // stretch that exists outside the Monday–Friday rule below.
        if market == .us {
            if weekday == 1 { return m >= 20 * 60 ? .overnight : .closed } // Sunday evening opens the week
            if (2...6).contains(weekday), m < 4 * 60 { return .overnight } // Mon–Fri small hours
            if (2...5).contains(weekday), m >= 20 * 60 { return .overnight } // Mon–Thu nights (Friday night has no session)
        }
        guard (2...6).contains(weekday) else { return .closed }

        switch market {
        case .sh, .sz:
            if (9 * 60 + 15)..<(11 * 60 + 30) ~= m { return .regular }  // Includes the opening call auction
            if (11 * 60 + 30)..<(13 * 60) ~= m { return .lunchBreak }
            if (13 * 60)..<(15 * 60) ~= m { return .regular }
            return .closed
        case .hk:
            if (9 * 60 + 30)..<(12 * 60) ~= m { return .regular }
            if (12 * 60)..<(13 * 60) ~= m { return .lunchBreak }
            if (13 * 60)..<(16 * 60 + 10) ~= m { return .regular }  // Includes the closing auction
            return .closed
        case .us:
            if (4 * 60)..<(9 * 60 + 30) ~= m { return .preMarket }
            if (9 * 60 + 30)..<(16 * 60) ~= m { return .regular }
            if (16 * 60)..<(20 * 60) ~= m { return .postMarket }
            return .closed
        case .jp:
            // Tokyo moved its close from 15:00 to 15:30 in November 2024; the
            // 11:30–12:30 lunch break has not changed.
            if (9 * 60)..<(11 * 60 + 30) ~= m { return .regular }
            if (11 * 60 + 30)..<(12 * 60 + 30) ~= m { return .lunchBreak }
            if (12 * 60 + 30)..<(15 * 60 + 30) ~= m { return .regular }
            return .closed
        case .kr, .kq:
            // Seoul runs one continuous session, closing auction included. Its
            // call auctions on either side are not modeled: no wired source
            // publishes them, so claiming the state would outrun the data.
            if (9 * 60)..<(15 * 60 + 30) ~= m { return .regular }
            return .closed
        case .crypto, .metal:
            return .regular
        case .metalCN:
            return .closed  // Handled above; every SHFE branch returns already.
        }
    }

    /// Whether this market is currently worth refreshing at high frequency.
    /// Overnight counts as inactive here: most sources have nothing new then, and the ones
    /// that do (Longbridge) declare it via `ProviderDescriptor.overnightMarkets`.
    public static func isActive(_ market: Market, at date: Date = .now) -> Bool {
        switch state(of: market, at: date) {
        case .regular, .preMarket, .postMarket: true
        case .closed, .lunchBreak, .overnight: false
        }
    }

    public static func anyActive(_ markets: some Sequence<Market>, at date: Date = .now) -> Bool {
        markets.contains { isActive($0, at: date) }
    }

    /// The trading day a moment belongs to, read in the market's own time zone.
    /// The US overnight session runs from 20:00 ET into the small hours, so it
    /// belongs to the session that follows it rather than the date it starts on.
    /// Metals keep their exchange calendar day: that is how both of their sources
    /// report them, whatever hour of the continuous session a bar falls in.
    public static func tradingDay(of market: Market, at date: Date) -> CalendarDay {
        let day = CalendarDay(date, in: market.timeZone)
        guard market == .us, state(of: market, at: date) == .overnight else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        let hour = calendar.component(.hour, from: date)
        // The 00:00–04:00 slice already carries the session's own date.
        guard hour >= 20, let next = calendar.date(byAdding: .day, value: 1, to: date) else { return day }
        return CalendarDay(next, in: market.timeZone)
    }
}

/// A calendar day identity: which day something happened on, not when. Days
/// read in different time zones (a trade date entered locally, a session date
/// read in the exchange's zone) compare directly instead of being turned back
/// into instants that would answer a different question.
public struct CalendarDay: Comparable, Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
