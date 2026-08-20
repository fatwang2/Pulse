import Foundation

/// Market identifier. Shanghai and Shenzhen are modeled separately (data sources use different symbol formats); the UI layer may merge them into a single "China A-shares" presentation.
public enum Market: String, Codable, Sendable, CaseIterable, Hashable {
    case us
    case hk
    case sh
    case sz
    case crypto
    /// Exchange-traded precious metals (COMEX / NYMEX). An asset class rather
    /// than a venue, the way `crypto` already is.
    case metal
    /// Shanghai Futures Exchange metals. Separate from `metal` because they are
    /// quoted in CNY on a Chinese session with a night leg — the two things a
    /// market owns — rather than in USD around the clock.
    case metalCN
    /// Tokyo Stock Exchange. Prime, Standard and Growth are one market here:
    /// they share a session, a currency, and a symbol format.
    case jp
    /// KOSPI, the Korea Exchange's main board.
    case kr
    /// KOSDAQ. Split from `kr` for the same reason `sz` is split from `sh` —
    /// sources address the two boards with different suffixes — and, unlike the
    /// Chinese boards, a Korean code carries no hint of which one it belongs to.
    case kq

    public var displayName: String {
        switch self {
        case .us: PulseLocalization.localizedString("market.us")
        case .hk: PulseLocalization.localizedString("market.hk")
        case .sh: PulseLocalization.localizedString("market.sh")
        case .sz: PulseLocalization.localizedString("market.sz")
        case .crypto: PulseLocalization.localizedString("market.crypto")
        // Both metal markets present as one asset class. The badge says what the
        // instrument is; which exchange it trades on is in its own name (上海金,
        // 沪金主连) and in the venue shown beside search results.
        case .metal, .metalCN: PulseLocalization.localizedString("market.metal")
        case .jp: PulseLocalization.localizedString("market.jp")
        // Both Korean boards present as one market. "KOSPI"/"KOSDAQ" does not fit
        // a badge, and which board a stock sits on is in its symbol (005930.KS).
        case .kr, .kq: PulseLocalization.localizedString("market.kr")
        }
    }

    public var currencyCode: String {
        switch self {
        case .us: "USD"
        case .hk: "HKD"
        case .sh, .sz, .metalCN: "CNY"
        case .crypto, .metal: "USD"
        case .jp: "JPY"
        case .kr, .kq: "KRW"
        }
    }

    public var timeZone: TimeZone {
        switch self {
        case .us: TimeZone(identifier: "America/New_York")!
        case .hk: TimeZone(identifier: "Asia/Hong_Kong")!
        case .sh, .sz, .metalCN: TimeZone(identifier: "Asia/Shanghai")!
        case .crypto: TimeZone(identifier: "UTC")!
        // Metals settle on New York exchange time, and their session boundaries
        // are quoted in it even though they trade nearly round the clock.
        case .metal: TimeZone(identifier: "America/New_York")!
        case .jp: TimeZone(identifier: "Asia/Tokyo")!
        case .kr, .kq: TimeZone(identifier: "Asia/Seoul")!
        }
    }

    public var timeZoneDisplayName: String {
        switch self {
        case .us: PulseLocalization.localizedString("market.timeZone.us")
        case .hk: PulseLocalization.localizedString("market.timeZone.hk")
        case .sh, .sz, .metalCN: PulseLocalization.localizedString("market.timeZone.cn")
        case .crypto: PulseLocalization.localizedString("market.timeZone.utc")
        case .metal: PulseLocalization.localizedString("market.timeZone.us")
        case .jp: PulseLocalization.localizedString("market.timeZone.jp")
        case .kr, .kq: PulseLocalization.localizedString("market.timeZone.kr")
        }
    }

    public var isChinaA: Bool { self == .sh || self == .sz }

    /// Whether this is one of the two Korea Exchange boards.
    public var isKorea: Bool { self == .kr || self == .kq }
}
