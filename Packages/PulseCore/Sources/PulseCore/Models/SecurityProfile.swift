import Foundation

/// What an instrument actually is: the business behind the ticker, plus where
/// the market files it. Static reference data — it changes on the scale of
/// corporate events, not quotes.
public struct SecurityProfile: Codable, Sendable, Hashable {
    public var symbol: SymbolID
    /// Business summary, in `localeIdentifier`'s language. Sources publish this
    /// in one language only, so it is not necessarily the app's.
    public var summary: String
    public var sector: String?
    public var industry: String?
    /// Language of `summary`, so surfaces can say which one they are showing.
    public var localeIdentifier: String

    public init(
        symbol: SymbolID,
        summary: String,
        sector: String? = nil,
        industry: String? = nil,
        localeIdentifier: String
    ) {
        self.symbol = symbol
        self.summary = summary
        self.sector = sector
        self.industry = industry
        self.localeIdentifier = localeIdentifier
    }

    /// Sector and industry as one line, skipping whichever the source omitted.
    public var classification: String? {
        let parts = [sector, industry]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
