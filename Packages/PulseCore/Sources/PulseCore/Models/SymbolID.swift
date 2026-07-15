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

/// Globally unique instrument identifier. Securities use a native exchange code;
/// cryptocurrencies use a structured base/quote pair rather than a provider-specific string.
public struct SymbolID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let market: Market
    private let storage: Storage

    private enum Storage: Hashable, Sendable {
        case securityCode(String)
        case cryptoPair(CryptoPair)
    }

    public init(market: Market, code: String) {
        self.market = market
        if market == .crypto, let pair = CryptoPair.parse(code) {
            storage = .cryptoPair(pair)
        } else {
            storage = .securityCode(Self.normalizeSecurityCode(code, market: market))
        }
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
        case .cryptoPair(let pair): pair.canonicalCode
        }
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
        case cryptoPair
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let market = try values.decode(Market.self, forKey: .market)
        self.market = market

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
            storage = .securityCode(Self.normalizeSecurityCode(code, market: market))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(market, forKey: .market)
        switch storage {
        case .securityCode(let code):
            try values.encode(code, forKey: .code)
        case .cryptoPair(let pair):
            try values.encode(pair, forKey: .cryptoPair)
        }
    }
}
