import Foundation

/// Globally unique identifier for an instrument: market + native exchange code.
/// Code normalization conventions: US uppercase letters (AAPL); HK digits with leading zeros stripped ("700"); Shanghai/Shenzhen 6-digit codes ("600519"); crypto pairs use Yahoo-style uppercase pairs (BTC-USD).
public struct SymbolID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let market: Market
    public let code: String

    public init(market: Market, code: String) {
        self.market = market
        self.code = Self.normalize(code: code, market: market)
    }

    public var description: String {
        switch market {
        case .us: code
        case .hk: "\(code).HK"
        case .sh: "\(code).SH"
        case .sz: "\(code).SZ"
        case .crypto: code
        }
    }

    static func normalize(code: String, market: Market) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        switch market {
        case .us, .crypto:
            return trimmed.uppercased()
        case .hk:
            // "00700" -> "700"; non-numeric codes are kept as is
            if trimmed.allSatisfy(\.isNumber), let n = Int(trimmed) { return String(n) }
            return trimmed.uppercased()
        case .sh, .sz:
            return trimmed
        }
    }

    /// Pads an HK code with leading zeros to the given width (Tencent uses 5 digits, Yahoo 4)
    public func paddedCode(width: Int) -> String {
        guard code.allSatisfy(\.isNumber), code.count < width else { return code }
        return String(repeating: "0", count: width - code.count) + code
    }
}
