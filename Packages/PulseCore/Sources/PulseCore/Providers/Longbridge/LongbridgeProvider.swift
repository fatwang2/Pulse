import Foundation

/// Longbridge OpenAPI quote source: real-time HK/US/CN quotes and candles over the
/// Longbridge binary socket protocol, authenticated with user-supplied credentials
/// (App Key / App Secret / Access Token from the developer center).
///
/// Pull-only for now; the same socket carries subscription push, which the future
/// real-time mode will build on via `quoteStream`.
public actor LongbridgeProvider: QuoteProvider {
    public static let providerID = "longbridge"

    private let socket = LongbridgeSocket()
    private var configured = false

    public init(auth: LongbridgeAuth? = nil) {
        Task { await self.updateAuth(auth) }
    }

    /// Swaps the auth mode at runtime (settings page); drops the connection so the next
    /// request authenticates freshly.
    public func updateAuth(_ auth: LongbridgeAuth?) async {
        switch auth {
        case .apiKey(let credentials) where credentials.isComplete:
            configured = true
            await socket.updateOTPSource { try await LongbridgeHTTP(credentials: credentials).fetchSocketOTP() }
        case .oauth(let session):
            configured = true
            await socket.updateOTPSource { try await session.fetchSocketOTP() }
        default:
            configured = false
            await socket.updateOTPSource(nil)
        }
    }

    public nonisolated var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: Self.providerID,
            name: PulseLocalization.localizedString("provider.longbridge"),
            markets: [.us, .hk, .sh, .sz],
            capabilities: [.quotes, .candles, .streaming],
            delay: [.us: 0, .hk: 0, .sh: 0, .sz: 0],
            rateLimit: RateLimitPolicy(minInterval: 0.12, batchSize: 500),
            credentials: [
                CredentialField(key: "appKey", label: "App Key", secure: false),
                CredentialField(key: "appSecret", label: "App Secret"),
                CredentialField(key: "accessToken", label: "Access Token"),
            ],
            // Push carries the liveliness; polling only reconciles and bootstraps
            suggestedPollInterval: 60,
            overnightMarkets: [.us]
        )
    }

    /// Exercises the full credential path (signed OTP request + socket auth + one quote pull).
    /// The settings page calls this when the user saves credentials.
    public func validateConnection() async throws {
        _ = try await quotes(for: [SymbolID(market: .hk, code: "700")])
    }

    // MARK: - QuoteProvider

    public func search(_ query: String) async throws -> [SymbolInfo] {
        throw ProviderError.unsupported(.search)
    }

    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        guard configured else { throw LongbridgeError.notConfigured }
        let mapped = symbols.compactMap { symbol in Self.longbridgeSymbol(for: symbol).map { (symbol, $0) } }
        guard !mapped.isEmpty else { return [] }

        let body = LongbridgeMessages.multiSecurityRequest(symbols: mapped.map(\.1))
        let responseBody = try await socket.request(.querySecurityQuote, body: body)
        let wireQuotes = try LongbridgeMessages.decodeSecurityQuoteResponse(responseBody)

        let symbolByLongbridge = Dictionary(uniqueKeysWithValues: mapped.map { ($0.1, $0.0) })
        return wireQuotes.compactMap { wire in
            guard let symbol = symbolByLongbridge[wire.symbol] else { return nil }
            return Self.quote(from: wire, symbol: symbol)
        }
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard configured else { throw LongbridgeError.notConfigured }
        guard let lbSymbol = Self.longbridgeSymbol(for: symbol),
              let lbPeriod = LongbridgeMessages.Period(period) else {
            throw ProviderError.symbolNotFound(symbol)
        }
        let body = LongbridgeMessages.candlestickRequest(symbol: lbSymbol, period: lbPeriod, count: count)
        let responseBody = try await socket.request(.queryCandlestick, body: body)
        return try LongbridgeMessages.decodeCandlestickResponse(responseBody)
    }

    // MARK: - Real-time push (subscription over the same socket)

    private struct StreamSubscriber {
        var symbols: Set<String>
        var continuation: AsyncThrowingStream<Quote, any Error>.Continuation
    }

    private var streamSubscribers: [UUID: StreamSubscriber] = [:]
    /// Latest full quote per Longbridge symbol; pushes carry deltas (no prev_close), so
    /// each push is merged over this base before being delivered.
    private var streamBase: [String: Quote] = [:]

    public nonisolated func quoteStream(for symbols: [SymbolID]) -> AsyncThrowingStream<Quote, any Error>? {
        AsyncThrowingStream { continuation in
            let id = UUID()
            let task = Task {
                await self.beginStream(id: id, symbols: symbols, continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.endStream(id: id) }
            }
        }
    }

    private func beginStream(id: UUID, symbols: [SymbolID],
                             continuation: AsyncThrowingStream<Quote, any Error>.Continuation) async {
        guard configured else {
            continuation.finish()
            return
        }
        let mapped = symbols.compactMap { symbol in Self.longbridgeSymbol(for: symbol).map { ($0, symbol) } }
        guard !mapped.isEmpty else {
            continuation.finish()
            return
        }

        await socket.setPushHandler { [weak self] command, body in
            guard let self, command == LongbridgeCommand.pushQuote.rawValue else { return }
            Task { await self.handleQuotePush(body) }
        }

        streamSubscribers[id] = StreamSubscriber(symbols: Set(mapped.map(\.0)), continuation: continuation)

        do {
            // Seed with full pull quotes: pushes lack prev_close, and the page wants a
            // complete snapshot immediately rather than waiting for the first tick.
            let seeded = try await quotes(for: symbols)
            for quote in seeded {
                if let lbSymbol = Self.longbridgeSymbol(for: quote.symbol) {
                    streamBase[lbSymbol] = quote
                }
                continuation.yield(quote)
            }
            let body = LongbridgeMessages.subscribeQuoteRequest(symbols: mapped.map(\.0))
            _ = try await socket.request(.subscribe, body: body)
        } catch {
            streamSubscribers[id] = nil
            continuation.finish(throwing: error)
        }
    }

    private func endStream(id: UUID) async {
        guard let ended = streamSubscribers.removeValue(forKey: id) else { return }
        let stillWanted = Set(streamSubscribers.values.flatMap(\.symbols))
        let orphaned = ended.symbols.subtracting(stillWanted)
        guard !orphaned.isEmpty else { return }
        for symbol in orphaned {
            streamBase[symbol] = nil
        }
        let body = LongbridgeMessages.unsubscribeQuoteRequest(symbols: Array(orphaned))
        _ = try? await socket.request(.unsubscribe, body: body)
    }

    private func handleQuotePush(_ body: Data) {
        guard let push = try? LongbridgeMessages.PushQuote(decoding: body),
              var quote = streamBase[push.symbol] else { return }
        if let price = push.lastDone { quote.price = price }
        if let open = push.open { quote.open = open }
        if let high = push.high { quote.high = high }
        if let low = push.low { quote.low = low }
        if push.volume > 0 { quote.volume = Double(push.volume) }
        if let turnover = push.turnover { quote.turnover = turnover }
        if push.timestamp > 0 { quote.timestamp = Date(timeIntervalSince1970: TimeInterval(push.timestamp)) }
        quote.marketState = push.marketState
        streamBase[push.symbol] = quote

        for subscriber in streamSubscribers.values where subscriber.symbols.contains(push.symbol) {
            subscriber.continuation.yield(quote)
        }
    }

    // MARK: - Mapping

    /// Pulse `SymbolID` → Longbridge `ticker.region`. Crypto is not covered by the
    /// OpenAPI quote packages, so it stays with the other providers.
    static func longbridgeSymbol(for symbol: SymbolID) -> String? {
        switch symbol.market {
        case .us: "\(symbol.code).US"
        case .hk: "\(symbol.code).HK"
        case .sh: "\(symbol.code).SH"
        case .sz: "\(symbol.code).SZ"
        case .crypto: nil
        }
    }

    static func quote(from wire: LongbridgeMessages.SecurityQuote, symbol: SymbolID) -> Quote? {
        guard let regularPrice = wire.lastDone, let prevClose = wire.prevClose else { return nil }

        var price = regularPrice
        var reference = prevClose
        var state: MarketState = .regular
        var timestamp = wire.timestamp

        // US extended sessions: surface the live session price the way the Yahoo path does,
        // with the change measured against that session's own reference close.
        if symbol.market == .us {
            let session: (quote: LongbridgeMessages.PrePostQuote?, state: MarketState)? =
                switch TradingCalendar.state(of: .us) {
                case .preMarket: (wire.preMarket, .preMarket)
                case .postMarket: (wire.postMarket, .postMarket)
                case .overnight: (wire.overnight, .overnight)
                // Weekend/holiday: surface the freshest extended-session close if it beats
                // the regular close (the timestamp guard below decides).
                case .closed: (wire.overnight, .overnight)
                default: nil
                }
            if let session, let sessionQuote = session.quote, let sessionPrice = sessionQuote.lastDone,
               sessionQuote.timestamp >= wire.timestamp {
                price = sessionPrice
                reference = sessionQuote.prevClose ?? regularPrice
                state = session.state
                timestamp = sessionQuote.timestamp
            }
        }

        return Quote(
            symbol: symbol,
            price: price,
            previousClose: reference,
            open: wire.open,
            high: wire.high,
            low: wire.low,
            volume: Double(wire.volume),
            turnover: wire.turnover,
            currencyCode: symbol.market.currencyCode,
            timestamp: timestamp > 0 ? Date(timeIntervalSince1970: TimeInterval(timestamp)) : .now,
            marketState: state
        )
    }
}
