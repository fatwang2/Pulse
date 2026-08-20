import Foundation

public enum InstrumentType: String, Codable, Sendable, Hashable {
    case equity, etf, index, fund, crypto, other
    /// Exchange-traded commodity contract (currently the precious metals).
    case commodity
}

/// A search result entry
public struct SymbolInfo: Codable, Sendable, Hashable, Identifiable {
    public var symbol: SymbolID
    public var name: String
    public var exchangeName: String?
    public var type: InstrumentType
    /// Filled by CompositeProvider so adding an item preserves which provider
    /// supplied its name and how that source ranks for this market.
    public var displayNameSource: DisplayNameSource?

    public init(
        symbol: SymbolID,
        name: String,
        exchangeName: String? = nil,
        type: InstrumentType = .equity,
        displayNameSource: DisplayNameSource? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.exchangeName = exchangeName
        self.type = type
        self.displayNameSource = displayNameSource
    }

    public var id: SymbolID { symbol }

    /// Search providers may spell the same index or metal contract differently.
    /// Pulse owns those canonical names; ordinary securities keep the
    /// search-result name.
    public var resolvedDisplayName: String {
        symbol.indexID?.displayName ?? symbol.metalID?.displayName ?? name
    }
}
