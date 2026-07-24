import Foundation

/// A localized canonical name returned by a provider's static reference-data API.
public struct SecurityName: Sendable, Hashable {
    public var symbol: SymbolID
    public var name: String
    public var localeIdentifier: String

    public init(symbol: SymbolID, name: String, localeIdentifier: String) {
        self.symbol = symbol
        self.name = name
        self.localeIdentifier = localeIdentifier
    }
}

/// A provider-ranked name ready to be compared with a watchlist's persisted
/// name watermark.
public struct SourcedSecurityName: Sendable, Hashable {
    public var symbol: SymbolID
    public var name: String
    public var source: DisplayNameSource

    public init(symbol: SymbolID, name: String, source: DisplayNameSource) {
        self.symbol = symbol
        self.name = name
        self.source = source
    }
}

/// Persisted provenance for a watchlist name. Lower priorities are preferred.
///
/// The numeric watermark intentionally survives temporary provider failure:
/// a lower-priority fallback may provide prices, but cannot rename the item.
public struct DisplayNameSource: Codable, Sendable, Hashable {
    public var providerID: String
    public var priority: Int
    public var localeIdentifier: String

    public init(providerID: String, priority: Int, localeIdentifier: String) {
        self.providerID = providerID
        self.priority = priority
        self.localeIdentifier = localeIdentifier
    }
}
