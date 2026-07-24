import Foundation

public enum ProviderError: Error, Sendable {
    case network(underlying: String)
    case rateLimited
    /// 4xx (except 429): a problem with the request itself (e.g. the source doesn't support the query), not a source failure
    case clientError(status: Int, detail: String)
    /// 5xx / decode failures etc.: an error on the data source side
    case badResponse(String)
    case unsupported(Capability)
    case symbolNotFound(SymbolID)

    /// Whether this error should trip the circuit breaker (temporarily take the data source offline).
    /// Request-level problems (4xx, symbol not found, unsupported capability) must not trip it — otherwise a single 400 from a Chinese search would wrongly kill the whole source.
    public var shouldTripCircuit: Bool {
        switch self {
        case .network, .rateLimited, .badResponse: true
        case .clientError, .unsupported, .symbolNotFound: false
        }
    }

    public static func shouldTrip(_ error: any Error) -> Bool {
        if error is CancellationError { return false }
        guard let providerError = error as? ProviderError else { return true }
        return providerError.shouldTripCircuit
    }
}

/// Unified protocol for all data sources (built-in / future Manifest plugins / JS plugins).
/// A Provider is only responsible for HOW to fetch data, never WHEN — scheduling, throttling, and caching all live in RefreshEngine.
public protocol QuoteProvider: Sendable {
    var descriptor: ProviderDescriptor { get }

    /// Searches for instruments (by code / name)
    func search(_ query: String) async throws -> [SymbolInfo]

    /// Resolves canonical localized names for already-known symbols.
    func securityNames(for symbols: [SymbolID]) async throws -> [SecurityName]

    /// Batch quote snapshots
    func quotes(for symbols: [SymbolID]) async throws -> [Quote]

    /// Candles / intraday data; returns the most recent `count` bars in ascending time order
    func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle]

    /// Real-time streaming (optional capability)
    func quoteStream(for symbols: [SymbolID]) -> AsyncThrowingStream<Quote, any Error>?
}

public extension QuoteProvider {
    func securityNames(for symbols: [SymbolID]) async throws -> [SecurityName] {
        throw ProviderError.unsupported(.referenceData)
    }

    func quoteStream(for symbols: [SymbolID]) -> AsyncThrowingStream<Quote, any Error>? { nil }
}
