import Foundation

/// One quote package negotiated by the official Longbridge SDK for the current
/// quote context. Package metadata is account/session data, not a static provider
/// capability: the same user can receive different packages in different clients.
public struct LongbridgeQuotePackage: Sendable, Hashable {
    public var key: String
    public var name: String
    public var description: String
    public var startAt: Date?
    public var endAt: Date?

    public init(
        key: String,
        name: String,
        description: String,
        startAt: Date? = nil,
        endAt: Date? = nil
    ) {
        self.key = key
        self.name = name
        self.description = description
        self.startAt = startAt
        self.endAt = endAt
    }

    func isActive(at date: Date) -> Bool {
        if let startAt, startAt > date { return false }
        if let endAt, endAt <= date { return false }
        return true
    }
}

/// Market-level access derived from the packages negotiated by the current SDK
/// session. `unknown` means the SDK returned no package that covers the market.
public enum LongbridgeQuoteAccess: String, Codable, Sendable, Hashable {
    case unknown
    case delayed
    case realtime
}

/// Converts the SDK's negotiated package metadata and market timestamp into the
/// delay carried by each quote. Package metadata is authoritative when present;
/// a near-exact 15-minute timestamp lag is a safety net for server/session drift.
enum LongbridgeQuoteFreshness {
    static let delayedQuoteInterval: TimeInterval = 15 * 60
    private static let freshTimestampTolerance: TimeInterval = 90
    private static let delayedTimestampTolerance: TimeInterval = 3 * 60

    static func packageDelay(
        for symbol: SymbolID,
        packages: [LongbridgeQuotePackage],
        at date: Date = .now
    ) -> TimeInterval? {
        let relevant = packages.filter {
            $0.isActive(at: date) && package($0, covers: symbol)
        }
        guard !relevant.isEmpty else { return nil }

        // Accounts commonly carry both HK Basic and HK L1. The best active
        // package wins, so a Basic row must never downgrade an active L1 row.
        if relevant.contains(where: isRealtimePackage) { return 0 }
        if relevant.contains(where: isDelayedPackage) { return delayedQuoteInterval }
        return nil
    }

    static func quoteAccess(
        for market: Market,
        packages: [LongbridgeQuotePackage],
        at date: Date = .now
    ) -> LongbridgeQuoteAccess {
        let representative = switch market {
        case .hk: SymbolID(market: .hk, code: "700")
        case .sh: SymbolID(market: .sh, code: "600000")
        case .sz: SymbolID(market: .sz, code: "000001")
        case .us: SymbolID(market: .us, code: "AAPL")
        case .crypto: SymbolID(cryptoBase: "BTC", quote: "USDT")
        }
        return switch packageDelay(for: representative, packages: packages, at: date) {
        case 0: .realtime
        case .some: .delayed
        case nil: .unknown
        }
    }

    static func effectiveDelay(
        for symbol: SymbolID,
        timestamp: Date,
        packages: [LongbridgeQuotePackage],
        receivedAt: Date = .now
    ) -> TimeInterval? {
        let declared = packageDelay(for: symbol, packages: packages, at: receivedAt)
        guard TradingCalendar.isActive(symbol.market, at: receivedAt) else { return declared }

        let age = max(0, receivedAt.timeIntervalSince(timestamp))
        if age <= freshTimestampTolerance {
            return declared
        }

        let delayedRange = (delayedQuoteInterval - delayedTimestampTolerance)
            ... (delayedQuoteInterval + delayedTimestampTolerance)
        if delayedRange.contains(age) {
            return max(declared ?? 0, delayedQuoteInterval)
        }
        return declared
    }

    private static func package(_ package: LongbridgeQuotePackage, covers symbol: SymbolID) -> Bool {
        let key = package.key.uppercased()
        let isIndexPackage = key.contains("INDEX")
        // Index-only rights must never upgrade an equity. Broad market packages
        // such as CN_Basic still cover indices in that market.
        if isIndexPackage && symbol.indexID == nil {
            return false
        }

        switch symbol.market {
        case .hk:
            return key.hasPrefix("HK_")
        case .sh, .sz:
            return key.hasPrefix("CN_")
        case .us:
            return key.hasPrefix("US_")
        case .crypto:
            return false
        }
    }

    private static func isRealtimePackage(_ package: LongbridgeQuotePackage) -> Bool {
        let text = searchableText(package)
        return text.contains("OPENAPI")
            || text.contains("L1")
            || text.contains("L2")
            || text.contains("QBBO")
            || text.contains("CONNECT")
            || text.contains("REALTIME")
            || text.contains("REAL-TIME")
            || text.contains("实时")
    }

    private static func isDelayedPackage(_ package: LongbridgeQuotePackage) -> Bool {
        let text = searchableText(package)
        return text.contains("BASIC")
            || text.contains("BMP")
            || text.contains("DELAY")
            || text.contains("15 MIN")
            || text.contains("15分钟")
            || text.contains("延迟")
    }

    private static func searchableText(_ package: LongbridgeQuotePackage) -> String {
        "\(package.key) \(package.name) \(package.description)".uppercased()
    }
}
