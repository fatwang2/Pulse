import Foundation

public enum InstrumentType: String, Codable, Sendable {
    case equity, etf, index, fund, crypto, other
}

/// A search result entry
public struct SymbolInfo: Codable, Sendable, Hashable, Identifiable {
    public var symbol: SymbolID
    public var name: String
    public var exchangeName: String?
    public var type: InstrumentType

    public init(symbol: SymbolID, name: String, exchangeName: String? = nil, type: InstrumentType = .equity) {
        self.symbol = symbol
        self.name = name
        self.exchangeName = exchangeName
        self.type = type
    }

    public var id: SymbolID { symbol }

    /// Search providers may spell the same index differently. Pulse owns the
    /// canonical index name; ordinary securities keep the search-result name.
    public var resolvedDisplayName: String {
        symbol.indexID?.displayName ?? name
    }
}
