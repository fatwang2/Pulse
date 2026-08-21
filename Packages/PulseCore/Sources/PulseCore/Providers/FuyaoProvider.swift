import Foundation

/// Fuyao (扶摇), Hithink/Tonghuashun's official A-share data service
/// (fuyao.aicubes.cn). BYOK: the user signs an API key with their Tonghuashun
/// account and every request carries it in `X-api-key`.
///
/// The service returns HTTP 200 for business errors too; the real outcome rides
/// the `code` field of a uniform ApiResponse envelope, so error mapping happens
/// on the envelope rather than the status line. Snapshots batch via
/// comma-separated `thscodes`; historical bars are day-only and one symbol per
/// request.
public actor FuyaoProvider: QuoteProvider {
    public static let providerID = "fuyao"
    static let baseURL = "https://fuyao.aicubes.cn"

    private let http: HTTPClient
    private var apiKey: String?

    public init(apiKey: String? = nil, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
        self.http = http
    }

    public func updateAPIKey(_ key: String?) {
        apiKey = key?.isEmpty == true ? nil : key
    }

    public nonisolated var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: Self.providerID,
            name: PulseLocalization.localizedString("provider.fuyao"),
            markets: [.sh, .sz],
            capabilities: [.quotes, .candles, .search],
            candlePeriods: [.day],
            delay: [.sh: 0, .sz: 0],
            // Measured (2026-08-22): a token bucket of capacity 20 with sub-second
            // refill — an 80-request concurrent burst never dipped X-RateLimit-Remaining
            // below 18, so the budget is effectively ~20 QPS. 0.5s spacing keeps an
            // order of magnitude of headroom.
            rateLimit: RateLimitPolicy(minInterval: 0.5, batchSize: 100),
            credentials: [CredentialField(key: "apiKey", label: "API Key")],
            suggestedPollInterval: 15
        )
    }

    /// Exercises authentication and one snapshot round-trip when a key is saved.
    public func validateConnection() async throws {
        _ = try await quotes(for: [SymbolID(market: .sh, code: "600519")])
    }

    // MARK: - Symbol mapping

    /// Fuyao serves exchange-listed A-share instruments addressed by thscode
    /// (`600519.SH`). Indices need the separate a-share-index endpoints, which
    /// Pulse does not route here yet.
    static func thscode(for id: SymbolID) -> String? {
        guard id.indexID == nil, id.metalID == nil, id.cryptoPair == nil else { return nil }
        switch id.market {
        case .sh: return id.code + ".SH"
        case .sz: return id.code + ".SZ"
        default: return nil
        }
    }

    static func symbolID(fromThscode thscode: String) -> SymbolID? {
        let parts = thscode.split(separator: ".")
        guard parts.count == 2 else { return nil }
        let market: Market? = switch parts[1] {
        case "SH": .sh
        case "SZ": .sz
        default: nil  // BJ (Beijing Stock Exchange) has no Market case yet
        }
        guard let market else { return nil }
        return SymbolID(market: market, code: String(parts[0]))
    }

    // MARK: - QuoteProvider

    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }
        let key = try requireKey()
        let batchSize = descriptor.rateLimit?.batchSize ?? 100
        var quotes: [Quote] = []
        for chunk in symbols.chunked(into: batchSize) {
            let mapping = Dictionary(uniqueKeysWithValues: chunk.compactMap { symbol in
                Self.thscode(for: symbol).map { ($0, symbol) }
            })
            guard !mapping.isEmpty else { continue }
            var components = URLComponents(string: "\(Self.baseURL)/api/a-share/prices/snapshot")!
            components.queryItems = [.init(name: "thscodes", value: mapping.keys.sorted().joined(separator: ","))]
            let data = try await http.get(components.url!, headers: ["X-api-key": key])
            quotes += try Self.parseQuotes(data: data, mapping: mapping)
        }
        guard !quotes.isEmpty else {
            // The envelope already said code=0: an empty result means Fuyao does not
            // carry these instruments, not that the source failed.
            throw ProviderError.clientError(status: 200, detail: "fuyao: no quotes parsed (unknown symbols?)")
        }
        return quotes
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard period == .day else { throw ProviderError.unsupported(.candles) }
        guard let thscode = Self.thscode(for: symbol) else { throw ProviderError.symbolNotFound(symbol) }
        let key = try requireKey()

        // Trading days are roughly 70% of calendar days; ask for double plus slack so
        // `count` bars survive holidays, capped just inside the API's 10-year window.
        let end = Date.now
        let spanDays = min(Double(count) * 2 + 30, 3600)
        let start = end.addingTimeInterval(-spanDays * 86_400)
        var components = URLComponents(string: "\(Self.baseURL)/api/a-share/prices/historical")!
        components.queryItems = [
            .init(name: "thscode", value: thscode),
            .init(name: "interval", value: "1d"),
            .init(name: "start", value: String(Int(start.timeIntervalSince1970 * 1000))),
            .init(name: "end", value: String(Int(end.timeIntervalSince1970 * 1000))),
            .init(name: "adjust", value: "forward"),
        ]
        let data = try await http.get(components.url!, headers: ["X-api-key": key])
        let candles = try Self.parseCandles(data: data)
        guard !candles.isEmpty else { throw ProviderError.symbolNotFound(symbol) }
        return Array(candles.suffix(count))
    }

    public func search(_ query: String) async throws -> [SymbolInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let key = try requireKey()
        var components = URLComponents(string: "\(Self.baseURL)/api/meta/tickers/search")!
        components.queryItems = [
            .init(name: "q", value: trimmed),
            // Exchange-traded instruments only: OTC funds have no exchange code, and
            // index thscodes collide with the equity code space (000001).
            .init(name: "asset_type", value: "a-share,fund-etf,fund-lof"),
            .init(name: "limit", value: "20"),
        ]
        let data = try await http.get(components.url!, headers: ["X-api-key": key])
        return try Self.parseSearch(data: data)
    }

    private func requireKey() throws -> String {
        guard let apiKey else {
            // Not a source failure: routing normally keeps an unconfigured Fuyao
            // disabled, so this only answers stray direct calls.
            throw ProviderError.clientError(status: 401, detail: "fuyao: no API key configured")
        }
        return apiKey
    }

    // MARK: - Envelope

    struct Envelope<Payload: Decodable>: Decodable {
        let code: Int
        let message: String?
        let data: Payload?
    }

    struct SnapshotPayload: Decodable {
        let timestamp: Double?
        let item: [SnapshotItem]?
    }

    struct SnapshotItem: Decodable {
        let thscode: String
        let lastPrice: Double?
        let prevPrice: Double?
        let openPrice: Double?
        let highPrice: Double?
        let lowPrice: Double?
        let volume: Double?
        let turnover: Double?
    }

    struct HistoricalPayload: Decodable {
        let item: [BarItem]?
    }

    struct BarItem: Decodable {
        let dateMs: Double
        let openPrice: Double?
        let highPrice: Double?
        let lowPrice: Double?
        let closePrice: Double?
        let volume: Double?
    }

    struct SearchPayload: Decodable {
        let item: [TickerItem]?
    }

    struct TickerItem: Decodable {
        let thscode: String
        let name: String
        let exchange: String?
        let assetType: String?
    }

    /// Decodes the uniform ApiResponse envelope and maps business error codes onto
    /// ProviderError; only quota (4001) and upstream failures (5xxx) may trip the
    /// circuit breaker.
    static func decodePayload<Payload: Decodable>(
        _ type: Payload.Type,
        from data: Data,
        endpoint: String
    ) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope: Envelope<Payload>
        do {
            envelope = try decoder.decode(Envelope<Payload>.self, from: data)
        } catch {
            throw ProviderError.badResponse("fuyao \(endpoint): \(error.localizedDescription)")
        }
        guard envelope.code == 0 else {
            throw providerError(code: envelope.code, message: envelope.message, endpoint: endpoint)
        }
        guard let payload = envelope.data else {
            throw ProviderError.badResponse("fuyao \(endpoint): success without data")
        }
        return payload
    }

    static func providerError(code: Int, message: String?, endpoint: String) -> ProviderError {
        let detail = "fuyao \(endpoint): code \(code) \(message ?? "")"
        return switch code {
        case 4001: .rateLimited
        case 1001...1999: .clientError(status: 400, detail: detail)
        case 2001, 2003: .clientError(status: 401, detail: detail)
        case 3001...3999: .clientError(status: 404, detail: detail)
        default: .badResponse(detail)
        }
    }

    // MARK: - Parsing

    static func parseQuotes(data: Data, mapping: [String: SymbolID]) throws -> [Quote] {
        let payload = try decodePayload(SnapshotPayload.self, from: data, endpoint: "snapshot")
        // One upstream-readiness timestamp for the whole batch, not per item.
        let timestamp = payload.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
        return (payload.item ?? []).compactMap { item in
            guard let symbol = mapping[item.thscode],
                  let price = item.lastPrice, price > 0,
                  let prevClose = item.prevPrice, prevClose > 0 else { return nil }
            return Quote(
                symbol: symbol,
                price: price,
                previousClose: prevClose,
                open: item.openPrice,
                high: item.highPrice,
                low: item.lowPrice,
                volume: item.volume,
                turnover: item.turnover,
                currencyCode: symbol.market.currencyCode,
                timestamp: timestamp
            )
        }
    }

    static func parseCandles(data: Data) throws -> [Candle] {
        let payload = try decodePayload(HistoricalPayload.self, from: data, endpoint: "historical")
        return (payload.item ?? []).compactMap { bar -> Candle? in
            guard let open = bar.openPrice, let high = bar.highPrice,
                  let low = bar.lowPrice, let close = bar.closePrice, close > 0 else { return nil }
            return Candle(
                time: Date(timeIntervalSince1970: bar.dateMs / 1000),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: bar.volume
            )
        }
        .sorted { $0.time < $1.time }
    }

    static func parseSearch(data: Data) throws -> [SymbolInfo] {
        let payload = try decodePayload(SearchPayload.self, from: data, endpoint: "search")
        return (payload.item ?? []).compactMap { item in
            guard let symbol = symbolID(fromThscode: item.thscode), !item.name.isEmpty else { return nil }
            let type: InstrumentType = switch item.assetType {
            case "a-share": .equity
            case "fund-etf": .etf
            case "fund-lof": .fund
            case "a-share-index": .index
            default: .other
            }
            return SymbolInfo(
                symbol: symbol,
                name: item.name,
                exchangeName: symbol.market.displayName,
                type: type
            )
        }
    }
}
