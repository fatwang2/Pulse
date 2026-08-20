import Foundation

/// Session bucket for a point on the intraday axis.
public enum IntradaySessionKind: Sendable, Hashable {
    case pre, regular, post
}

/// One exchange trading day expressed in trading minutes. Lunch breaks collapse to a
/// single x-axis boundary so every surface can position intraday points identically.
///
/// When built with `includesExtendedHours` (US only), the pre-market (4:00–9:30 ET) and
/// post-market (16:00–20:00 ET) sessions attach as compressed "wings" on either side of
/// the regular session: each wing maps onto 15% of the plot width, leaving 70% for the
/// regular session — the layout mainstream brokerage apps use. The regular session keeps
/// its 0...totalMinutes coordinates, so wings extend the axis outward instead of shifting it.
public struct IntradayTradingSession: Sendable, Hashable {
    public let open: Date
    public let morningEnd: Date?
    public let afternoonStart: Date?
    public let close: Date
    /// Extended-hours wing bounds; nil when the session covers regular hours only.
    public let preOpen: Date?
    public let postClose: Date?

    public init(market: Market, referenceDate: Date, includesExtendedHours: Bool = false) {
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
        case .jp:
            open = at(9, 0)
            morningEnd = at(11, 30)
            afternoonStart = at(12, 30)
            close = at(15, 30)
        case .kr, .kq:
            open = at(9, 0)
            morningEnd = nil
            afternoonStart = nil
            close = at(15, 30)
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
        case .metal:
            // One metal session runs 18:00 ET through 17:00 ET the next day, and
            // the axis follows it rather than the calendar day: London spot is
            // only quoted from the session open, so a midnight axis would strand
            // its line in the right quarter of an otherwise empty plot. Framing
            // the session also trims the older bars Yahoo returns for `GC=F`
            // (its window starts at midnight) down to the session on screen.
            let openDay = calendar.component(.hour, from: referenceDate) >= 18
                ? day
                : calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let nextDay = calendar.date(byAdding: .day, value: 1, to: openDay) ?? openDay
            func at(_ hour: Int, _ minute: Int, of base: Date) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
            }
            open = at(18, 0, of: openDay)
            morningEnd = nil
            afternoonStart = nil
            close = at(17, 0, of: nextDay)
        case .metalCN:
            // One Shanghai trading day opens with the night session at 20:00 and
            // settles at 15:30 the next afternoon — the union of the two
            // exchanges' hours. The 02:30–09:00 gap collapses onto the axis
            // exactly the way an A-share lunch break does.
            let openDay = calendar.component(.hour, from: referenceDate) >= 20
                ? day
                : calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let nextDay = calendar.date(byAdding: .day, value: 1, to: openDay) ?? openDay
            func at(_ hour: Int, _ minute: Int, of base: Date) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
            }
            open = at(20, 0, of: openDay)
            morningEnd = at(2, 30, of: nextDay)
            afternoonStart = at(9, 0, of: nextDay)
            close = at(15, 30, of: nextDay)
        }
        if includesExtendedHours, market == .us {
            preOpen = at(4, 0)
            postClose = at(20, 0)
        } else {
            preOpen = nil
            postClose = nil
        }
    }

    public var morningMinutes: Double {
        (morningEnd ?? close).timeIntervalSince(open) / 60
    }

    public var totalMinutes: Double {
        guard let afternoonStart else { return morningMinutes }
        return morningMinutes + close.timeIntervalSince(afternoonStart) / 60
    }

    // MARK: - Extended-hours wings

    public var includesExtendedHours: Bool { preOpen != nil || postClose != nil }

    /// Axis width of each wing: 15% of the plot against the regular session's 70%.
    private var wingAxisMinutes: Double { totalMinutes * 3 / 14 }

    public var preAxisMinutes: Double { preOpen == nil ? 0 : wingAxisMinutes }
    public var postAxisMinutes: Double { postClose == nil ? 0 : wingAxisMinutes }

    /// Chart x-domain, wings included. Equals 0...totalMinutes for regular-only sessions.
    public var axisLowerBound: Double { -preAxisMinutes }
    public var axisUpperBound: Double { totalMinutes + postAxisMinutes }

    public func sessionKind(for date: Date) -> IntradaySessionKind {
        if preOpen != nil, date < open { return .pre }
        if postClose != nil, date > close { return .post }
        return .regular
    }

    /// Keeps US intraday bars inside the user-selected chart session across every
    /// trading day in a historical series. Extended mode intentionally means
    /// pre-market + regular + post-market (04:00–20:00 ET), not overnight trading.
    public static func filterCandles(
        _ candles: [Candle],
        market: Market,
        includesExtendedHours: Bool
    ) -> [Candle] {
        guard market == .us else { return candles }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        let lowerMinute = includesExtendedHours ? 4 * 60 : 9 * 60 + 30
        let upperMinute = includesExtendedHours ? 20 * 60 : 16 * 60
        return candles.filter { candle in
            let components = calendar.dateComponents([.hour, .minute], from: candle.time)
            let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            return minute >= lowerMinute && minute <= upperMinute
        }
    }

    /// Classifies a US intraday bar for subtle pre/post chart shading.
    public static func usSessionKind(for date: Date) -> IntradaySessionKind {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.us.timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if minute < 9 * 60 + 30 { return .pre }
        if minute > 16 * 60 { return .post }
        return .regular
    }

    /// Includes a one-minute tolerance for providers that timestamp the opening/closing bucket edge.
    public func contains(_ date: Date) -> Bool {
        let start = preOpen ?? open
        let end = postClose ?? close
        return date >= start.addingTimeInterval(-60) && date <= end.addingTimeInterval(60)
    }

    /// Wall-clock date → axis-minute offset; lunch collapses onto the morning close and
    /// extended-hours wings compress linearly onto their fixed axis widths.
    public func minuteOffset(for date: Date) -> Double {
        if date <= open { return preWingOffset(for: date) }
        if date > close { return postWingOffset(for: date) }
        if let morningEnd, let afternoonStart {
            if date <= morningEnd { return date.timeIntervalSince(open) / 60 }
            if date < afternoonStart { return morningMinutes }
            return min(morningMinutes + date.timeIntervalSince(afternoonStart) / 60, totalMinutes)
        }
        return min(date.timeIntervalSince(open) / 60, totalMinutes)
    }

    /// Axis-minute offset → wall-clock date, using the afternoon side of the lunch boundary.
    public func date(forMinute minute: Double) -> Date {
        if minute < 0, let preOpen, preAxisMinutes > 0 {
            let fraction = min(max(1 + minute / preAxisMinutes, 0), 1)
            return preOpen.addingTimeInterval(fraction * open.timeIntervalSince(preOpen))
        }
        if minute > totalMinutes, let postClose, postAxisMinutes > 0 {
            let fraction = min(max((minute - totalMinutes) / postAxisMinutes, 0), 1)
            return close.addingTimeInterval(fraction * postClose.timeIntervalSince(close))
        }
        if let afternoonStart, minute > morningMinutes {
            return afternoonStart.addingTimeInterval((minute - morningMinutes) * 60)
        }
        return open.addingTimeInterval(minute * 60)
    }

    private func preWingOffset(for date: Date) -> Double {
        guard let preOpen else { return 0 }
        let span = open.timeIntervalSince(preOpen)
        guard span > 0 else { return 0 }
        let fraction = min(max(date.timeIntervalSince(preOpen) / span, 0), 1)
        return (fraction - 1) * preAxisMinutes
    }

    private func postWingOffset(for date: Date) -> Double {
        guard let postClose else { return totalMinutes }
        let span = postClose.timeIntervalSince(close)
        guard span > 0 else { return totalMinutes }
        let fraction = min(max(date.timeIntervalSince(close) / span, 0), 1)
        return totalMinutes + fraction * postAxisMinutes
    }
}

/// Canonical current-session series shared by the list, detail chart, and share cards.
public struct IntradayTrendSnapshot: Sendable, Hashable {
    public let session: IntradayTradingSession
    public let candles: [Candle]

    public init(candles: [Candle], market: Market, includesExtendedHours: Bool = false) {
        // Providers return ascending series; only pay for a sort when one actually arrives unordered.
        var sorted = candles
        if !sorted.isSortedByTime { sorted.sort { $0.time < $1.time } }
        let extended = includesExtendedHours && market == .us
        let session = Self.anchorSession(for: sorted, market: market, includesExtendedHours: extended)
        self.session = session
        self.candles = sorted.filter { session.contains($0.time) }
    }

    /// Fetches may carry pre/post (or overnight) bars, so anchor the displayed day on the newest
    /// candle that falls inside its own day's session frame — otherwise a morning with only
    /// pre-market bars would frame "today" and leave the regular chart empty.
    ///
    /// Session frames construct `Calendar`s, which are far too expensive to build per candle
    /// (this runs on every chart body evaluation). Instead hop day by day: probe a frame, use
    /// cheap date comparisons to find the newest candle at or before its upper bound, and only
    /// when that candle sits below the frame's lower bound (an overnight stray or a data gap)
    /// re-frame from the previous calendar day. A few hops cover weekends and gaps.
    private static func anchorSession(
        for sorted: [Candle],
        market: Market,
        includesExtendedHours: Bool
    ) -> IntradayTradingSession {
        func frame(_ date: Date) -> IntradayTradingSession {
            IntradayTradingSession(market: market, referenceDate: date,
                                   includesExtendedHours: includesExtendedHours)
        }
        guard var probe = sorted.last?.time else { return frame(.now) }
        for _ in 0..<6 {
            let candidate = frame(probe)
            let lower = (candidate.preOpen ?? candidate.open).addingTimeInterval(-60)
            let upper = (candidate.postClose ?? candidate.close).addingTimeInterval(60)
            guard let newest = sorted.last(where: { $0.time <= upper })?.time else { break }
            if newest >= lower { return candidate }
            // Hop far enough to land in the previous calendar day, then re-frame from there.
            probe = lower.addingTimeInterval(-12 * 3600)
        }
        return frame(probe)
    }

    public static func recommendedCandleCount(for market: Market) -> Int {
        switch market {
        case .crypto: 24 * 60
        // A metal session is 23 hours long; ask for a little more so the closing
        // minute still fits.
        case .metal: 1_400
        // A Shanghai session is 390 night minutes plus 390 day minutes.
        case .metalCN: 800
        // Longbridge's All session can contain 1,440 minute slots: overnight 480 +
        // pre 330 + regular 390 + post 240. Its API caps a page at 1,000, so the
        // provider loads 1,000 recent rows plus a 600-row older page when needed.
        case .us: 1_600
        case .sh, .sz, .hk: 400
        // Tokyo trades 330 minutes, Seoul 390.
        case .jp, .kr, .kq: 400
        }
    }
}

private extension [Candle] {
    var isSortedByTime: Bool {
        var previous = Date.distantPast
        for candle in self {
            if candle.time < previous { return false }
            previous = candle.time
        }
        return true
    }
}
