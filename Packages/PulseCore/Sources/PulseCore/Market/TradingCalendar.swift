import Foundation

public enum SessionState: String, Sendable {
    case closed, preMarket, regular, lunchBreak, postMarket
}

/// Trading sessions per market (in each exchange's time zone).
/// TODO: holiday calendar (Chinese New Year / National Day / Thanksgiving, etc.); the MVP uses a simple Monday-to-Friday rule.
public enum TradingCalendar {
    public static func state(of market: Market, at date: Date = .now) -> SessionState {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = comps.weekday, (2...6).contains(weekday),
              let hour = comps.hour, let minute = comps.minute else { return .closed }
        let m = hour * 60 + minute

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
        }
    }

    /// Whether this market is currently worth refreshing at high frequency
    public static func isActive(_ market: Market, at date: Date = .now) -> Bool {
        switch state(of: market, at: date) {
        case .regular, .preMarket, .postMarket: true
        case .closed, .lunchBreak: false
        }
    }

    public static func anyActive(_ markets: some Sequence<Market>, at date: Date = .now) -> Bool {
        markets.contains { isActive($0, at: date) }
    }
}
