import Foundation

/// Provider-independent identity of a cryptocurrency market.
/// Providers are responsible for converting it to their wire format (`BTCUSDT`, `BTC-USD`, etc.).
public struct CryptoPair: Hashable, Codable, Sendable {
    public let baseAsset: String
    public let quoteAsset: String

    public init(baseAsset: String, quoteAsset: String) {
        self.baseAsset = Self.normalize(asset: baseAsset)
        self.quoteAsset = Self.normalize(asset: quoteAsset)
    }

    public var canonicalCode: String { "\(baseAsset)-\(quoteAsset)" }
    public var displayCode: String { "\(baseAsset)/\(quoteAsset)" }

    static func parse(_ raw: String) -> CryptoPair? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let separator = normalized.contains("/") ? "/" : "-"
        let parts = normalized.split(separator: Character(separator), omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let pair = CryptoPair(baseAsset: String(parts[0]), quoteAsset: String(parts[1]))
        guard !pair.baseAsset.isEmpty, !pair.quoteAsset.isEmpty else { return nil }
        return pair
    }

    private static func normalize(asset: String) -> String {
        asset.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private enum CodingKeys: String, CodingKey {
        case baseAsset
        case quoteAsset
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            baseAsset: try values.decode(String.self, forKey: .baseAsset),
            quoteAsset: try values.decode(String.self, forKey: .quoteAsset)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(baseAsset, forKey: .baseAsset)
        try values.encode(quoteAsset, forKey: .quoteAsset)
    }
}

/// Provider-independent identities for indices whose wire symbols differ across
/// market-data vendors. Stocks and ETFs can use their exchange ticker directly;
/// indices cannot (`sp500` is `.SPX.US` at Longbridge, `^GSPC` at Yahoo, and
/// `INX` at Tencent).
public enum MarketIndexID: String, Codable, Sendable, CaseIterable {
    case sp500
    case nasdaqComposite
    case dowJonesIndustrial
    case nasdaq100
    case vix
    case russell1000
    case russell2000
    case hangSeng
    case hangSengTech
    case shanghaiComposite
    case shenzhenComponent
    case chiNext

    public var market: Market {
        switch self {
        case .sp500, .nasdaqComposite, .dowJonesIndustrial, .nasdaq100,
             .vix, .russell1000, .russell2000:
            .us
        case .hangSeng, .hangSengTech:
            .hk
        case .shanghaiComposite:
            .sh
        case .shenzhenComponent, .chiNext:
            .sz
        }
    }

    /// Stable user-facing shorthand; providers must not send this value directly.
    public var displayCode: String {
        switch self {
        case .sp500: "SPX"
        case .nasdaqComposite: "IXIC"
        case .dowJonesIndustrial: "DJI"
        case .nasdaq100: "NDX"
        case .vix: "VIX"
        case .russell1000: "RUI"
        case .russell2000: "RUT"
        case .hangSeng: "HSI"
        case .hangSengTech: "HSTECH"
        case .shanghaiComposite: "000001"
        case .shenzhenComponent: "399001"
        case .chiNext: "399006"
        }
    }

    /// Code written alongside `indexID` so the immediately preceding app version
    /// can still decode a new watchlist snapshot.
    var backwardCompatibleCode: String {
        switch self {
        case .sp500: "^GSPC"
        case .nasdaqComposite: "^IXIC"
        case .dowJonesIndustrial: "^DJI"
        case .nasdaq100: "^NDX"
        case .vix: "^VIX"
        case .russell1000: "^RUI"
        case .russell2000: "^RUT"
        case .hangSeng: "HSI"
        case .hangSengTech: "HSTECH"
        case .shanghaiComposite: "000001"
        case .shenzhenComponent: "399001"
        case .chiNext: "399006"
        }
    }

    /// Recognizes legacy codes from every built-in provider and collapses them to
    /// one semantic identity. Unknown indices remain ordinary SymbolIDs until an
    /// explicit alias is added; they still benefit from generic per-symbol fallback.
    static func resolve(market: Market, code rawCode: String) -> MarketIndexID? {
        var code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch market {
        case .us:
            if code.hasSuffix(".US") { code.removeLast(3) }
            switch code {
            case "SPX", "^SPX", ".SPX", "GSPC", "^GSPC", "INX", "^INX", ".INX":
                return .sp500
            case "IXIC", "^IXIC", ".IXIC", "^COMP":
                return .nasdaqComposite
            case "DJI", "^DJI", ".DJI":
                return .dowJonesIndustrial
            case "NDX", "^NDX", ".NDX":
                return .nasdaq100
            case "VIX", "^VIX", ".VIX":
                return .vix
            case "RUI", "^RUI", ".RUI":
                return .russell1000
            case "RUT", "^RUT", ".RUT":
                return .russell2000
            default:
                return nil
            }
        case .hk:
            if code.hasSuffix(".HK") { code.removeLast(3) }
            switch code {
            case "HSI", "^HSI": return .hangSeng
            case "HSTECH", "^HSTECH": return .hangSengTech
            default: return nil
            }
        case .sh:
            if code.hasSuffix(".SH") || code.hasSuffix(".SS") { code.removeLast(3) }
            return code == "000001" ? .shanghaiComposite : nil
        case .sz:
            if code.hasSuffix(".SZ") { code.removeLast(3) }
            switch code {
            case "399001": return .shenzhenComponent
            case "399006": return .chiNext
            default: return nil
            }
        case .crypto:
            return nil
        }
    }
}

/// Globally unique instrument identifier. Stocks and ETFs use a native exchange
/// code, indices use a semantic identity, and cryptocurrencies use a structured pair.
public struct SymbolID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let market: Market
    private let storage: Storage

    private enum Storage: Hashable, Sendable {
        case securityCode(String)
        case marketIndex(MarketIndexID)
        case cryptoPair(CryptoPair)
    }

    public init(market: Market, code: String) {
        if market == .crypto, let pair = CryptoPair.parse(code) {
            self.market = market
            storage = .cryptoPair(pair)
        } else if let index = MarketIndexID.resolve(market: market, code: code) {
            self.market = index.market
            storage = .marketIndex(index)
        } else {
            self.market = market
            storage = .securityCode(Self.normalizeSecurityCode(code, market: market))
        }
    }

    public init(index: MarketIndexID) {
        market = index.market
        storage = .marketIndex(index)
    }

    public init(cryptoPair: CryptoPair) {
        market = .crypto
        storage = .cryptoPair(cryptoPair)
    }

    public init(cryptoBase baseAsset: String, quote quoteAsset: String) {
        self.init(cryptoPair: CryptoPair(baseAsset: baseAsset, quoteAsset: quoteAsset))
    }

    /// Compatibility accessor for call sites that need a compact, provider-independent code.
    /// Crypto identity is not stored in this representation; it is derived from `cryptoPair`.
    public var code: String {
        switch storage {
        case .securityCode(let code): code
        case .marketIndex(let index): index.displayCode
        case .cryptoPair(let pair): pair.canonicalCode
        }
    }

    public var indexID: MarketIndexID? {
        guard case .marketIndex(let index) = storage else { return nil }
        return index
    }

    public var cryptoPair: CryptoPair? {
        guard case .cryptoPair(let pair) = storage else { return nil }
        return pair
    }

    public var displayCode: String {
        cryptoPair?.displayCode ?? code
    }

    public var currencyCode: String {
        cryptoPair?.quoteAsset ?? market.currencyCode
    }

    public var description: String {
        switch market {
        case .us: code
        case .hk: "\(code).HK"
        case .sh: "\(code).SH"
        case .sz: "\(code).SZ"
        case .crypto: displayCode
        }
    }

    private static func normalizeSecurityCode(_ code: String, market: Market) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        switch market {
        case .us, .crypto:
            return trimmed.uppercased()
        case .hk:
            // "00700" -> "700"; non-numeric codes are kept as is.
            if trimmed.allSatisfy(\.isNumber), let number = Int(trimmed) { return String(number) }
            return trimmed.uppercased()
        case .sh, .sz:
            return trimmed
        }
    }

    /// Pads an HK code with leading zeros to the given width (Tencent uses 5 digits, Yahoo 4).
    public func paddedCode(width: Int) -> String {
        guard code.allSatisfy(\.isNumber), code.count < width else { return code }
        return String(repeating: "0", count: width - code.count) + code
    }

    // MARK: - Persistence

    private enum CodingKeys: String, CodingKey {
        case market
        case code
        case indexID
        case cryptoPair
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let market = try values.decode(Market.self, forKey: .market)
        self.market = market

        if let index = try values.decodeIfPresent(MarketIndexID.self, forKey: .indexID) {
            guard index.market == market else {
                throw DecodingError.dataCorruptedError(
                    forKey: .indexID,
                    in: values,
                    debugDescription: "Index \(index.rawValue) does not belong to market \(market)"
                )
            }
            storage = .marketIndex(index)
            return
        }

        if market == .crypto {
            if let pair = try values.decodeIfPresent(CryptoPair.self, forKey: .cryptoPair) {
                storage = .cryptoPair(pair)
                return
            }

            // v1 stored Yahoo-style strings such as BTC-USD. Binance is now the canonical
            // crypto market source, so legacy USD pairs migrate to their USDT spot pair.
            let legacyCode = try values.decode(String.self, forKey: .code)
            if var pair = CryptoPair.parse(legacyCode) {
                if pair.quoteAsset == "USD" {
                    pair = CryptoPair(baseAsset: pair.baseAsset, quoteAsset: "USDT")
                }
                storage = .cryptoPair(pair)
            } else {
                storage = .securityCode(Self.normalizeSecurityCode(legacyCode, market: market))
            }
        } else {
            let code = try values.decode(String.self, forKey: .code)
            if let index = MarketIndexID.resolve(market: market, code: code) {
                storage = .marketIndex(index)
            } else {
                storage = .securityCode(Self.normalizeSecurityCode(code, market: market))
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(market, forKey: .market)
        switch storage {
        case .securityCode(let code):
            try values.encode(code, forKey: .code)
        case .marketIndex(let index):
            try values.encode(index.backwardCompatibleCode, forKey: .code)
            try values.encode(index, forKey: .indexID)
        case .cryptoPair(let pair):
            try values.encode(pair, forKey: .cryptoPair)
        }
    }
}
