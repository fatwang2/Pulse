import Foundation

public enum SessionState: String, Sendable {
    case closed, preMarket, regular, lunchBreak, postMarket
    /// US overnight session (Sun 20:00 ET through Fri 04:00 ET, in nightly slices)
    case overnight
}

/// Trading sessions per market (in each exchange's time zone).
/// TODO: holiday calendar (Chinese New Year / National Day / Thanksgiving, etc.); the MVP uses a simple Monday-to-Friday rule.
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
        case .crypto:
            return .regular
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
}
