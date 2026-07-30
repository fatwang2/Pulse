#if os(macOS)
import Darwin
import CryptoKit
import Foundation
import LongbridgeCABI
import OSLog

private let longbridgeLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.pulse.mac",
    category: "Longbridge"
)

private typealias LBSDKAsyncCallback = @convention(c) (UnsafePointer<lb_async_result_t>?) -> Void
private typealias LBSDKQuoteCallback = @convention(c) (
    OpaquePointer?,
    UnsafePointer<lb_push_quote_t>?,
    UnsafeMutableRawPointer?
) -> Void
private typealias LBSDKFreeCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void

private final class LBSDKAsyncBox: @unchecked Sendable {
    let completion: (UnsafePointer<lb_async_result_t>) -> Void

    init(completion: @escaping (UnsafePointer<lb_async_result_t>) -> Void) {
        self.completion = completion
    }
}

private let longbridgeSDKAsyncCallback: LBSDKAsyncCallback = { result in
    guard let result, let userdata = result.pointee.userdata else { return }
    let box = Unmanaged<LBSDKAsyncBox>.fromOpaque(userdata).takeRetainedValue()
    box.completion(result)
}

private struct LBSDKPrePostQuote: Sendable {
    var lastDone: Double?
    var timestamp: Int64
    var volume: Int64
    var turnover: Double?
    var high: Double?
    var low: Double?
    var previousClose: Double?
}

private struct LBSDKSecurityQuote: Sendable {
    var symbol: String
    var lastDone: Double?
    var previousClose: Double?
    var open: Double?
    var high: Double?
    var low: Double?
    var timestamp: Int64
    var volume: Int64
    var turnover: Double?
    var preMarket: LBSDKPrePostQuote?
    var postMarket: LBSDKPrePostQuote?
    var overnight: LBSDKPrePostQuote?
}

private struct LBSDKSecurityName: Sendable {
    var symbol: String
    var nameCN: String
    var nameEN: String
    var nameHK: String
}

private struct LBSDKPushQuote: Sendable {
    var symbol: String
    var lastDone: Double?
    var open: Double?
    var high: Double?
    var low: Double?
    var timestamp: Int64
    var volume: Int64
    var turnover: Double?
    var tradeSession: Int32
}

private struct LBSDKCandlestick: Sendable {
    var close: Double?
    var open: Double?
    var low: Double?
    var high: Double?
    var volume: Int64
    var timestamp: Int64
}

private struct LBSDKQuotePackage: Sendable {
    var key: String
    var name: String
    var description: String
    var startAt: Int64
    var endAt: Int64
}

enum LongbridgeSDKErrorClassifier {
    static func providerError(code: Int64, message: String) -> ProviderError {
        let lowercased = message.lowercased()
        if lowercased.contains("rate limit") || lowercased.contains("too many") || code == 429 {
            return .rateLimited
        }
        if isInvalidSymbol(code: code, message: message) {
            return .clientError(
                status: 400,
                detail: "Longbridge SDK \(code): \(message)"
            )
        }
        if lowercased.contains("token")
            || lowercased.contains("auth")
            || lowercased.contains("permission")
            || code == 401
            || code == 403 {
            return .clientError(status: Int(code == 0 ? 401 : code), detail: message)
        }
        if lowercased.contains("network")
            || lowercased.contains("connect")
            || lowercased.contains("socket")
            || lowercased.contains("timeout")
            || lowercased.contains("timed out") {
            return .network(underlying: message)
        }
        return .badResponse("Longbridge SDK \(code): \(message)")
    }

    static func isInvalidSymbol(_ error: any Error) -> Bool {
        guard let providerError = error as? ProviderError,
              case .clientError(_, let detail) = providerError else {
            return false
        }
        return isInvalidSymbol(code: 0, message: detail)
    }

    private static func isInvalidSymbol(code: Int64, message: String) -> Bool {
        let lowercased = message.lowercased()
        return code == 301_600
            || lowercased.contains("301600")
            || lowercased.contains("invalid symbol")
            || lowercased.contains("symbol not found")
            || lowercased.contains("security not found")
            || lowercased.contains("security does not exist")
    }
}

private final class LongbridgeSDKDynamicLibrary: @unchecked Sendable {
    typealias ConfigFromAPIKey = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> OpaquePointer?
    typealias ConfigFromOAuthToken = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
    typealias ConfigMutation = @convention(c) (OpaquePointer?) -> Void
    typealias ConfigStringMutation = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?
    ) -> Void
    typealias ConfigFree = @convention(c) (OpaquePointer?) -> Void
    typealias ContextNew = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias ContextRelease = @convention(c) (OpaquePointer?) -> Void
    typealias ContextRequest = @convention(c) (
        OpaquePointer?,
        LBSDKAsyncCallback?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias SetOnQuote = @convention(c) (
        OpaquePointer?,
        LBSDKQuoteCallback?,
        UnsafeMutableRawPointer?,
        LBSDKFreeCallback?
    ) -> Void
    typealias SymbolsRequest = @convention(c) (
        OpaquePointer?,
        UnsafePointer<UnsafePointer<CChar>?>?,
        UInt,
        LBSDKAsyncCallback?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias SubscriptionRequest = @convention(c) (
        OpaquePointer?,
        UnsafePointer<UnsafePointer<CChar>?>?,
        UInt,
        UInt8,
        LBSDKAsyncCallback?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias CandlesticksRequest = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        Int32,
        UInt,
        Int32,
        Int32,
        LBSDKAsyncCallback?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias HistoryCandlesticksByOffsetRequest = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        Int32,
        Int32,
        Bool,
        UnsafePointer<lb_datetime_t>?,
        UInt,
        Int32,
        LBSDKAsyncCallback?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias DecimalToDouble = @convention(c) (OpaquePointer?) -> Double
    typealias ErrorMessage = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    typealias ErrorCode = @convention(c) (OpaquePointer?) -> Int64

    let handle: UnsafeMutableRawPointer
    let configFromAPIKey: ConfigFromAPIKey
    let configFromOAuthToken: ConfigFromOAuthToken
    let enableOvernight: ConfigMutation
    let disablePrintQuotePackages: ConfigMutation
    let setHTTPURL: ConfigStringMutation
    let setQuoteWebSocketURL: ConfigStringMutation
    let configFree: ConfigFree
    let contextNew: ContextNew
    let contextRetain: ContextRelease
    let contextRelease: ContextRelease
    let quotePackageDetails: ContextRequest
    let setOnQuote: SetOnQuote
    let staticInfo: SymbolsRequest
    let quote: SymbolsRequest
    let subscribe: SubscriptionRequest
    let unsubscribe: SubscriptionRequest
    let candlesticks: CandlesticksRequest
    let historyCandlesticksByOffset: HistoryCandlesticksByOffsetRequest
    let decimalToDouble: DecimalToDouble
    let errorMessage: ErrorMessage
    let errorCode: ErrorCode

    init() throws {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else {
            throw LongbridgeError.socket("Pulse has no built-in PlugIns directory")
        }
        let executableURL = pluginsURL
            .appendingPathComponent("PulseLongbridgePlugin.bundle", isDirectory: true)
            .appendingPathComponent("Contents/MacOS/PulseLongbridgePlugin", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw LongbridgeError.socket("Longbridge SDK plugin is missing at \(executableURL.path)")
        }

        dlerror()
        guard let handle = dlopen(executableURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let detail = dlerror().map { String(cString: $0) } ?? "unknown loader error"
            throw LongbridgeError.socket("Unable to load Longbridge SDK: \(detail)")
        }
        self.handle = handle
        self.configFromAPIKey = try Self.resolve(handle, "lb_config_from_apikey", as: ConfigFromAPIKey.self)
        self.configFromOAuthToken = try Self.resolve(
            handle,
            "lb_config_from_oauth_token",
            as: ConfigFromOAuthToken.self
        )
        self.enableOvernight = try Self.resolve(
            handle,
            "lb_config_enable_overnight",
            as: ConfigMutation.self
        )
        self.disablePrintQuotePackages = try Self.resolve(
            handle,
            "lb_config_disable_print_quote_packages",
            as: ConfigMutation.self
        )
        self.setHTTPURL = try Self.resolve(
            handle,
            "lb_config_set_http_url",
            as: ConfigStringMutation.self
        )
        self.setQuoteWebSocketURL = try Self.resolve(
            handle,
            "lb_config_set_quote_ws_url",
            as: ConfigStringMutation.self
        )
        self.configFree = try Self.resolve(handle, "lb_config_free", as: ConfigFree.self)
        self.contextNew = try Self.resolve(handle, "lb_quote_context_new", as: ContextNew.self)
        self.contextRetain = try Self.resolve(
            handle,
            "lb_quote_context_retain",
            as: ContextRelease.self
        )
        self.contextRelease = try Self.resolve(
            handle,
            "lb_quote_context_release",
            as: ContextRelease.self
        )
        self.quotePackageDetails = try Self.resolve(
            handle,
            "lb_quote_context_quote_package_details",
            as: ContextRequest.self
        )
        self.setOnQuote = try Self.resolve(
            handle,
            "lb_quote_context_set_on_quote",
            as: SetOnQuote.self
        )
        self.staticInfo = try Self.resolve(
            handle,
            "lb_quote_context_static_info",
            as: SymbolsRequest.self
        )
        self.quote = try Self.resolve(handle, "lb_quote_context_quote", as: SymbolsRequest.self)
        self.subscribe = try Self.resolve(
            handle,
            "lb_quote_context_subscribe",
            as: SubscriptionRequest.self
        )
        self.unsubscribe = try Self.resolve(
            handle,
            "lb_quote_context_unsubscribe",
            as: SubscriptionRequest.self
        )
        self.candlesticks = try Self.resolve(
            handle,
            "lb_quote_context_candlesticks",
            as: CandlesticksRequest.self
        )
        self.historyCandlesticksByOffset = try Self.resolve(
            handle,
            "lb_quote_context_history_candlesticks_by_offset",
            as: HistoryCandlesticksByOffsetRequest.self
        )
        self.decimalToDouble = try Self.resolve(
            handle,
            "lb_decimal_to_double",
            as: DecimalToDouble.self
        )
        self.errorMessage = try Self.resolve(handle, "lb_error_message", as: ErrorMessage.self)
        self.errorCode = try Self.resolve(handle, "lb_error_code", as: ErrorCode.self)
    }

    private static func resolve<Function>(
        _ handle: UnsafeMutableRawPointer,
        _ name: String,
        as type: Function.Type
    ) throws -> Function {
        dlerror()
        guard let symbol = dlsym(handle, name) else {
            let detail = dlerror().map { String(cString: $0) } ?? "symbol not found"
            throw LongbridgeError.socket("Longbridge SDK ABI mismatch for \(name): \(detail)")
        }
        return unsafeBitCast(symbol, to: type)
    }

    func decimal(_ pointer: OpaquePointer?) -> Double? {
        guard let pointer else { return nil }
        return decimalToDouble(pointer)
    }

    func providerError(_ pointer: OpaquePointer) -> ProviderError {
        let message = errorMessage(pointer).map { String(cString: $0) } ?? "unknown SDK error"
        let code = errorCode(pointer)
        return LongbridgeSDKErrorClassifier.providerError(code: code, message: message)
    }

    func copySecurityQuotes(_ result: UnsafePointer<lb_async_result_t>) throws -> [LBSDKSecurityQuote] {
        guard let data = result.pointee.data else { return [] }
        let rows = UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: lb_security_quote_t.self),
            count: Int(result.pointee.length)
        )
        return rows.compactMap { row in
            guard let symbol = row.symbol else { return nil }
            return LBSDKSecurityQuote(
                symbol: String(cString: symbol),
                lastDone: decimal(row.last_done),
                previousClose: decimal(row.prev_close),
                open: decimal(row.open),
                high: decimal(row.high),
                low: decimal(row.low),
                timestamp: row.timestamp,
                volume: row.volume,
                turnover: decimal(row.turnover),
                preMarket: copyPrePost(row.pre_market_quote),
                postMarket: copyPrePost(row.post_market_quote),
                overnight: copyPrePost(row.overnight_quote)
            )
        }
    }

    func copySecurityNames(_ result: UnsafePointer<lb_async_result_t>) -> [LBSDKSecurityName] {
        guard let data = result.pointee.data else { return [] }
        let rows = UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: lb_security_static_info_t.self),
            count: Int(result.pointee.length)
        )
        return rows.compactMap { row in
            guard let symbol = row.symbol else { return nil }
            return LBSDKSecurityName(
                symbol: String(cString: symbol),
                nameCN: row.name_cn.map(String.init(cString:)) ?? "",
                nameEN: row.name_en.map(String.init(cString:)) ?? "",
                nameHK: row.name_hk.map(String.init(cString:)) ?? ""
            )
        }
    }

    func copyCandlesticks(_ result: UnsafePointer<lb_async_result_t>) -> [LBSDKCandlestick] {
        guard let data = result.pointee.data else { return [] }
        let rows = UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: lb_candlestick_t.self),
            count: Int(result.pointee.length)
        )
        return rows.map { row in
            LBSDKCandlestick(
                close: decimal(row.close),
                open: decimal(row.open),
                low: decimal(row.low),
                high: decimal(row.high),
                volume: row.volume,
                timestamp: row.timestamp
            )
        }
    }

    func copyQuotePackages(_ result: UnsafePointer<lb_async_result_t>) -> [LBSDKQuotePackage] {
        guard let data = result.pointee.data else { return [] }
        let rows = UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: lb_quote_package_detail_t.self),
            count: Int(result.pointee.length)
        )
        return rows.map { row in
            LBSDKQuotePackage(
                key: row.key.map(String.init(cString:)) ?? "",
                name: row.name.map(String.init(cString:)) ?? "",
                description: row.description.map(String.init(cString:)) ?? "",
                startAt: row.start_at,
                endAt: row.end_at
            )
        }
    }

    func copyPushQuote(_ pointer: UnsafePointer<lb_push_quote_t>) -> LBSDKPushQuote? {
        let row = pointer.pointee
        guard let symbol = row.symbol else { return nil }
        return LBSDKPushQuote(
            symbol: String(cString: symbol),
            lastDone: decimal(row.last_done),
            open: decimal(row.open),
            high: decimal(row.high),
            low: decimal(row.low),
            timestamp: row.timestamp,
            volume: row.volume,
            turnover: decimal(row.turnover),
            tradeSession: row.trade_session
        )
    }

    private func copyPrePost(_ pointer: UnsafePointer<lb_prepost_quote_t>?) -> LBSDKPrePostQuote? {
        guard let row = pointer?.pointee else { return nil }
        return LBSDKPrePostQuote(
            lastDone: decimal(row.last_done),
            timestamp: row.timestamp,
            volume: row.volume,
            turnover: decimal(row.turnover),
            high: decimal(row.high),
            low: decimal(row.low),
            previousClose: decimal(row.prev_close)
        )
    }
}

private final class LBSDKPushBox: @unchecked Sendable {
    let library: LongbridgeSDKDynamicLibrary
    let handler: @Sendable (LBSDKPushQuote) -> Void

    init(
        library: LongbridgeSDKDynamicLibrary,
        handler: @escaping @Sendable (LBSDKPushQuote) -> Void
    ) {
        self.library = library
        self.handler = handler
    }

    func receive(_ quote: UnsafePointer<lb_push_quote_t>) {
        guard let snapshot = library.copyPushQuote(quote) else { return }
        handler(snapshot)
    }
}

private let longbridgeSDKQuoteCallback: LBSDKQuoteCallback = { _, quote, userdata in
    guard let quote, let userdata else { return }
    let box = Unmanaged<LBSDKPushBox>.fromOpaque(userdata).takeUnretainedValue()
    box.receive(quote)
}

private let longbridgeSDKFreeCallback: LBSDKFreeCallback = { userdata in
    guard let userdata else { return }
    Unmanaged<LBSDKPushBox>.fromOpaque(userdata).release()
}

/// Keeps Pulse's provider contract while delegating quote snapshots, candlesticks,
/// WebSocket reconnect, and resubscription to the official SDK.
actor LongbridgeSDKBridge {
    private struct StreamSubscriber {
        var symbols: Set<String>
        var continuation: AsyncThrowingStream<Quote, any Error>.Continuation
    }

    private struct FreshnessLogState {
        var signature: String
        var loggedAt: Date
    }

    private var auth: LongbridgeAuth?
    private var library: LongbridgeSDKDynamicLibrary?
    private var context: OpaquePointer?
    private var status: LongbridgeConnectionStatus = .disconnected
    private var statusContinuation: AsyncStream<LongbridgeConnectionStatus>.Continuation?
    private var streamSubscribers: [UUID: StreamSubscriber] = [:]
    private var subscribedSymbols: Set<String> = []
    private var streamBase: [String: Quote] = [:]
    private var negotiatedQuotePackages: [LongbridgeQuotePackage] = []
    private var freshnessLogState: [Market: FreshnessLogState] = [:]
    private var marketsWithLoggedPush: Set<Market> = []

    init(auth: LongbridgeAuth?) {
        self.auth = auth
    }

    func updateAuth(_ auth: LongbridgeAuth?) {
        longbridgeLogger.notice("Authentication changed; rebuilding quote context")
        finishStreams()
        releaseContext()
        self.auth = auth
        setStatus(.disconnected)
    }

    func statusUpdates() -> AsyncStream<LongbridgeConnectionStatus> {
        statusContinuation?.finish()
        let pair = AsyncStream<LongbridgeConnectionStatus>.makeStream()
        statusContinuation = pair.continuation
        pair.continuation.yield(status)
        return pair.stream
    }

    func resetConnection() {
        longbridgeLogger.notice("Manual quote connection reset requested")
        finishStreams()
        releaseContext()
        setStatus(.disconnected)
    }

    func quotePackages() async throws -> [LongbridgeQuotePackage] {
        _ = try await ensureContext()
        return negotiatedQuotePackages
    }

    func subscriptionRoundTrip(for symbols: [SymbolID]) async throws {
        let requested = Set(symbols.compactMap(LongbridgeProvider.longbridgeSymbol(for:)))
        let isolated = requested.subtracting(subscribedSymbols)
        guard !isolated.isEmpty else { return }

        do {
            _ = try await ensureContext()
            let accepted = try await subscribeSupportedSymbols(Array(isolated))
            if !accepted.isEmpty {
                try await changeSubscription(symbols: Array(accepted), subscribe: false)
            }
            setStatus(.connected)
        } catch {
            recordFailure(error)
            throw error
        }
    }

    func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        let mapped = symbols.compactMap { symbol in
            LongbridgeProvider.longbridgeSymbol(for: symbol).map { (symbol, $0) }
        }
        guard !mapped.isEmpty else { return [] }

        do {
            let context = try await ensureContext()
            let library = try requireLibrary()
            let snapshots = try await requestSecurityQuotes(
                symbols: mapped.map(\.1),
                context: context,
                library: library
            )
            let receivedAt = Date.now
            let packages = negotiatedQuotePackages
            let symbolsBySDKName = Dictionary(uniqueKeysWithValues: mapped.map { ($0.1, $0.0) })
            let quotes = snapshots.compactMap { snapshot -> Quote? in
                guard let symbol = symbolsBySDKName[snapshot.symbol] else { return nil }
                return Self.quote(
                    from: snapshot,
                    symbol: symbol,
                    packages: packages,
                    receivedAt: receivedAt
                )
            }
            for quote in quotes {
                if let sdkSymbol = LongbridgeProvider.longbridgeSymbol(for: quote.symbol) {
                    streamBase[sdkSymbol] = quote
                }
            }
            logQuoteFreshness(quotes, receivedAt: receivedAt)
            setStatus(.connected)
            return quotes
        } catch {
            recordFailure(error)
            throw error
        }
    }

    func securityNames(for symbols: [SymbolID]) async throws -> [SecurityName] {
        let mapped = symbols.compactMap { symbol in
            LongbridgeProvider.longbridgeSymbol(for: symbol).map { (symbol, $0) }
        }
        guard !mapped.isEmpty else { return [] }

        do {
            let context = try await ensureContext()
            let library = try requireLibrary()
            let snapshots = try await requestSecurityNames(
                symbols: mapped.map(\.1),
                context: context,
                library: library
            )
            let symbolsBySDKName = Dictionary(uniqueKeysWithValues: mapped.map { ($0.1, $0.0) })
            let localeIdentifier = PulseLocalization.currentLanguageIdentifier
            let names = snapshots.compactMap { snapshot -> SecurityName? in
                guard let symbol = symbolsBySDKName[snapshot.symbol],
                      let name = Self.preferredName(
                        from: snapshot,
                        localeIdentifier: localeIdentifier
                      ) else {
                    return nil
                }
                return SecurityName(
                    symbol: symbol,
                    name: name,
                    localeIdentifier: localeIdentifier
                )
            }
            setStatus(.connected)
            return names
        } catch {
            recordFailure(error)
            throw error
        }
    }

    func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard let sdkSymbol = LongbridgeProvider.longbridgeSymbol(for: symbol) else {
            throw ProviderError.symbolNotFound(symbol)
        }
        let sdkPeriod = Self.sdkPeriod(period)
        let requestedCount = max(1, count)
        let latestPageCount = min(requestedCount, LongbridgeMinuteCandleBackfill.apiPageLimit)
        // lb_trade_sessions_t: 0 = Intraday, 100 = All. Fetch all US sessions for
        // intraday resolutions, then let the chart apply the user's pre/post preference.
        // Overnight bars may come along too and are removed by the presentation filter.
        let sdkTradeSessions: Int32 = (symbol.market == .us && period.isIntraday) ? 100 : 0

        do {
            let context = try await ensureContext()
            let library = try requireLibrary()
            // The actor can process an auth change or manual reset while either page
            // awaits its callback. Keep this context alive across the complete paged
            // operation even if releaseContext() drops the actor-owned reference.
            library.contextRetain(context)
            defer { library.contextRelease(context) }
            let snapshots: [LBSDKCandlestick] = try await perform(library: library) { callback, userdata in
                sdkSymbol.withCString { symbolPointer in
                    library.candlesticks(
                        context,
                        symbolPointer,
                        sdkPeriod,
                        UInt(latestPageCount),
                        0,
                        sdkTradeSessions,
                        callback,
                        userdata
                    )
                }
            } decode: { result in
                library.copyCandlesticks(result)
            }
            // The SDK request itself is not cancellable. If the user switched periods
            // while the latest page was in flight, do not amplify that stale request
            // with another 600-row history page.
            try Task.checkCancellation()
            let latestCandles = Self.candles(from: snapshots)
            var candles = latestCandles

            let olderPageCount = min(
                max(0, requestedCount - latestPageCount),
                LongbridgeMinuteCandleBackfill.apiPageLimit
            )
            if olderPageCount > 0,
               LongbridgeMinuteCandleBackfill.needsOlderPage(
                latestCandles,
                market: symbol.market,
                period: period,
                latestPageReachedLimit: snapshots.count == latestPageCount
               ),
               let earliest = latestCandles.min(by: { $0.time < $1.time }) {
                var before = Self.sdkDateTime(for: earliest.time, market: symbol.market)
                do {
                    let olderSnapshots: [LBSDKCandlestick] = try await perform(
                        library: library
                    ) { callback, userdata in
                        sdkSymbol.withCString { symbolPointer in
                            withUnsafePointer(to: &before) { timePointer in
                                library.historyCandlesticksByOffset(
                                    context,
                                    symbolPointer,
                                    sdkPeriod,
                                    0,
                                    false,
                                    timePointer,
                                    UInt(olderPageCount),
                                    sdkTradeSessions,
                                    callback,
                                    userdata
                                )
                            }
                        }
                    } decode: { result in
                        library.copyCandlesticks(result)
                    }
                    // SDK calls cannot be cancelled in flight. Discard a completed
                    // backfill if the caller switched periods while it was running.
                    try Task.checkCancellation()
                    candles = LongbridgeMinuteCandleBackfill.merge(
                        older: Self.candles(from: olderSnapshots),
                        latest: latestCandles,
                        limit: requestedCount
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Backfill is an enhancement: the latest page is still complete
                    // enough to render and must not mark quotes unhealthy.
                    longbridgeLogger.warning(
                        "Minute candle backfill failed; using latest page issue=\(Self.issueLabel(for: error), privacy: .public)"
                    )
                }
            }
            setStatus(.connected)
            return candles.sorted { $0.time < $1.time }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            recordFailure(error)
            throw error
        }
    }

    nonisolated func quoteStream(
        for symbols: [SymbolID]
    ) -> AsyncThrowingStream<Quote, any Error> {
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

    private func beginStream(
        id: UUID,
        symbols: [SymbolID],
        continuation: AsyncThrowingStream<Quote, any Error>.Continuation
    ) async {
        let mapped = symbols.compactMap { symbol in
            LongbridgeProvider.longbridgeSymbol(for: symbol).map { ($0, symbol) }
        }
        guard !mapped.isEmpty else {
            continuation.finish()
            return
        }

        do {
            let seeded = try await quotes(for: symbols)
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }
            for quote in seeded {
                continuation.yield(quote)
            }

            let wanted = Set(mapped.map(\.0))
            let alreadySubscribed = wanted.intersection(subscribedSymbols)
            let newSymbols = wanted.subtracting(subscribedSymbols)
            var accepted = alreadySubscribed
            if !newSymbols.isEmpty {
                let newlyAccepted = try await subscribeSupportedSymbols(Array(newSymbols))
                accepted.formUnion(newlyAccepted)
                subscribedSymbols.formUnion(newlyAccepted)
            }
            guard !accepted.isEmpty else {
                continuation.finish()
                setStatus(.connected)
                return
            }
            streamSubscribers[id] = StreamSubscriber(symbols: accepted, continuation: continuation)
            let markets = Set(mapped.compactMap { sdkSymbol, symbol in
                accepted.contains(sdkSymbol) ? symbol.market : nil
            })
            let marketList = markets.map(\.rawValue).sorted().joined(separator: ",")
            longbridgeLogger.info(
                "Quote stream subscribed markets=\(marketList, privacy: .public) count=\(accepted.count, privacy: .public)"
            )
            setStatus(.connected)
        } catch {
            streamSubscribers[id] = nil
            recordFailure(error)
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
        if context != nil {
            try? await changeSubscription(symbols: Array(orphaned), subscribe: false)
        }
        subscribedSymbols.subtract(orphaned)
    }

    private func changeSubscription(symbols: [String], subscribe: Bool) async throws {
        guard let context else { throw LongbridgeError.notConfigured }
        let library = try requireLibrary()
        let function = subscribe ? library.subscribe : library.unsubscribe
        let _: Void = try await perform(library: library) { callback, userdata in
            Self.withCStringArray(symbols) { pointers, count in
                function(context, pointers, count, 1, callback, userdata)
            }
        } decode: { _ in () }
    }

    /// Longbridge rejects an entire subscription request when one symbol is invalid.
    /// Bisect request-level failures so supported symbols remain live and only the
    /// offending leaf is excluded.
    private func subscribeSupportedSymbols(_ symbols: [String]) async throws -> Set<String> {
        let symbols = symbols.sorted()
        guard !symbols.isEmpty else { return [] }
        do {
            try await changeSubscription(symbols: symbols, subscribe: true)
            return Set(symbols)
        } catch where LongbridgeSDKErrorClassifier.isInvalidSymbol(error) {
            guard symbols.count > 1 else { return [] }
            let midpoint = symbols.count / 2
            let left = try await subscribeSupportedSymbols(Array(symbols[..<midpoint]))
            do {
                let right = try await subscribeSupportedSymbols(Array(symbols[midpoint...]))
                return left.union(right)
            } catch {
                // A later infrastructure failure must not leave the successfully
                // isolated left half subscribed without an owning stream.
                if !left.isEmpty {
                    try? await changeSubscription(symbols: Array(left), subscribe: false)
                }
                throw error
            }
        }
    }

    /// Quote snapshots have the same all-or-nothing invalid-symbol behavior as
    /// subscriptions. Preserve the valid parts of a mixed batch.
    private func requestSecurityQuotes(
        symbols: [String],
        context: OpaquePointer,
        library: LongbridgeSDKDynamicLibrary
    ) async throws -> [LBSDKSecurityQuote] {
        guard !symbols.isEmpty else { return [] }
        do {
            return try await perform(library: library) { callback, userdata in
                Self.withCStringArray(symbols) { pointers, count in
                    library.quote(context, pointers, count, callback, userdata)
                }
            } decode: { result in
                try library.copySecurityQuotes(result)
            }
        } catch where LongbridgeSDKErrorClassifier.isInvalidSymbol(error) {
            guard symbols.count > 1 else { return [] }
            let midpoint = symbols.count / 2
            let left = try await requestSecurityQuotes(
                symbols: Array(symbols[..<midpoint]),
                context: context,
                library: library
            )
            let right = try await requestSecurityQuotes(
                symbols: Array(symbols[midpoint...]),
                context: context,
                library: library
            )
            return left + right
        }
    }

    /// Static-info requests reject a mixed batch when one symbol is unknown.
    /// Isolate that leaf so one unsupported instrument cannot block every name.
    private func requestSecurityNames(
        symbols: [String],
        context: OpaquePointer,
        library: LongbridgeSDKDynamicLibrary
    ) async throws -> [LBSDKSecurityName] {
        guard !symbols.isEmpty else { return [] }
        do {
            return try await perform(library: library) { callback, userdata in
                Self.withCStringArray(symbols) { pointers, count in
                    library.staticInfo(context, pointers, count, callback, userdata)
                }
            } decode: { result in
                library.copySecurityNames(result)
            }
        } catch where LongbridgeSDKErrorClassifier.isInvalidSymbol(error) {
            guard symbols.count > 1 else { return [] }
            let midpoint = symbols.count / 2
            let left = try await requestSecurityNames(
                symbols: Array(symbols[..<midpoint]),
                context: context,
                library: library
            )
            let right = try await requestSecurityNames(
                symbols: Array(symbols[midpoint...]),
                context: context,
                library: library
            )
            return left + right
        }
    }

    private func receivePush(_ push: LBSDKPushQuote) {
        guard var quote = streamBase[push.symbol] else { return }
        if let value = push.lastDone { quote.price = value }
        if let value = push.open { quote.open = value }
        if let value = push.high { quote.high = value }
        if let value = push.low { quote.low = value }
        quote.volume = Double(push.volume)
        if let value = push.turnover { quote.turnover = value }
        if push.timestamp > 0 {
            quote.timestamp = Date(timeIntervalSince1970: TimeInterval(push.timestamp))
        }
        quote.sourceDelay = LongbridgeQuoteFreshness.effectiveDelay(
            for: quote.symbol,
            timestamp: quote.timestamp,
            packages: negotiatedQuotePackages
        )
        quote.marketState = Self.marketState(forTradeSession: push.tradeSession)
        streamBase[push.symbol] = quote
        if marketsWithLoggedPush.insert(quote.symbol.market).inserted {
            let age = max(0, Int(Date.now.timeIntervalSince(quote.timestamp)))
            longbridgeLogger.info(
                "First quote push market=\(quote.symbol.market.rawValue, privacy: .public) ageSeconds=\(age, privacy: .public)"
            )
        }
        setStatus(.connected)

        for subscriber in streamSubscribers.values where subscriber.symbols.contains(push.symbol) {
            subscriber.continuation.yield(quote)
        }
    }

    private func ensureContext() async throws -> OpaquePointer {
        if let context { return context }
        guard let auth else { throw LongbridgeError.notConfigured }

        setStatus(.connecting)
        let library: LongbridgeSDKDynamicLibrary
        if let existing = self.library {
            library = existing
        } else {
            library = try LongbridgeSDKDynamicLibrary()
            self.library = library
        }

        let config: OpaquePointer?
        let authMode: String
        let authClientFingerprint: String
        switch auth {
        case .apiKey(let credentials):
            authMode = "api-key"
            authClientFingerprint = Self.fingerprint(credentials.appKey)
            config = credentials.appKey.withCString { appKey in
                credentials.appSecret.withCString { appSecret in
                    credentials.accessToken.withCString { accessToken in
                        library.configFromAPIKey(appKey, appSecret, accessToken)
                    }
                }
            }
        case .oauth(let session):
            authMode = "oauth"
            authClientFingerprint = await session.clientFingerprint()
            let accessToken = try await session.accessTokenForSDK()
            config = accessToken.withCString { library.configFromOAuthToken($0) }
        }
        guard let config else {
            throw LongbridgeError.socket("Longbridge SDK could not create an authenticated config")
        }
        defer { library.configFree(config) }

        library.enableOvernight(config)
        library.disablePrintQuotePackages(config)
        let usesChinaEndpoint = LongbridgeEndpointSelection.usesChinaEndpoint()
        if usesChinaEndpoint {
            LongbridgeEndpointSelection.httpBaseURL().absoluteString.withCString {
                library.setHTTPURL(config, $0)
            }
            LongbridgeEndpointSelection.quoteWebSocketURL().absoluteString.withCString {
                library.setQuoteWebSocketURL(config, $0)
            }
        }
        longbridgeLogger.notice(
            "Creating quote context auth=\(authMode, privacy: .public) authClient=\(authClientFingerprint, privacy: .public) endpoint=\(usesChinaEndpoint ? "cn" : "global", privacy: .public)"
        )
        guard let context = library.contextNew(config) else {
            throw LongbridgeError.socket("Longbridge SDK could not create a quote context")
        }
        self.context = context

        let pushBox = LBSDKPushBox(library: library) { [weak self] push in
            Task { await self?.receivePush(push) }
        }
        library.setOnQuote(
            context,
            longbridgeSDKQuoteCallback,
            Unmanaged.passRetained(pushBox).toOpaque(),
            longbridgeSDKFreeCallback
        )

        do {
            negotiatedQuotePackages = try await requestQuotePackages(
                context: context,
                library: library
            )
            let keys = negotiatedQuotePackages
                .map(\.key)
                .filter { !$0.isEmpty }
                .sorted()
                .joined(separator: ",")
            longbridgeLogger.notice(
                "Quote packages negotiated count=\(self.negotiatedQuotePackages.count, privacy: .public) keys=\(keys, privacy: .public)"
            )
        } catch {
            negotiatedQuotePackages = []
            longbridgeLogger.error(
                "Quote package inspection failed issue=\(Self.issueLabel(for: error), privacy: .public)"
            )
        }
        return context
    }

    private func releaseContext() {
        if let context, let library {
            library.contextRelease(context)
        }
        context = nil
        subscribedSymbols = []
        streamBase = [:]
        negotiatedQuotePackages = []
        freshnessLogState = [:]
        marketsWithLoggedPush = []
    }

    private func finishStreams() {
        for subscriber in streamSubscribers.values {
            subscriber.continuation.finish()
        }
        streamSubscribers = [:]
        subscribedSymbols = []
        streamBase = [:]
    }

    private func requireLibrary() throws -> LongbridgeSDKDynamicLibrary {
        guard let library else {
            throw LongbridgeError.socket("Longbridge SDK has not been loaded")
        }
        return library
    }

    private func perform<Value: Sendable>(
        library: LongbridgeSDKDynamicLibrary,
        invoke: (_ callback: LBSDKAsyncCallback, _ userdata: UnsafeMutableRawPointer) -> Void,
        decode: @escaping (UnsafePointer<lb_async_result_t>) throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let box = LBSDKAsyncBox { result in
                do {
                    if let sdkError = result.pointee.error {
                        throw library.providerError(sdkError)
                    }
                    continuation.resume(returning: try decode(result))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            invoke(longbridgeSDKAsyncCallback, Unmanaged.passRetained(box).toOpaque())
        }
    }

    private func setStatus(_ newStatus: LongbridgeConnectionStatus) {
        guard status != newStatus else { return }
        status = newStatus
        longbridgeLogger.notice(
            "Connection status=\(Self.statusLabel(newStatus), privacy: .public)"
        )
        statusContinuation?.yield(newStatus)
    }

    private func recordFailure(_ error: any Error) {
        if LongbridgeSDKErrorClassifier.isInvalidSymbol(error) {
            if context != nil { setStatus(.connected) }
            return
        }
        longbridgeLogger.error(
            "Longbridge operation failed issue=\(Self.issueLabel(for: error), privacy: .public)"
        )
        setStatus(.failed(Self.connectionIssue(for: error)))
    }

    private func requestQuotePackages(
        context: OpaquePointer,
        library: LongbridgeSDKDynamicLibrary
    ) async throws -> [LongbridgeQuotePackage] {
        let rows: [LBSDKQuotePackage] = try await perform(library: library) { callback, userdata in
            library.quotePackageDetails(context, callback, userdata)
        } decode: { result in
            library.copyQuotePackages(result)
        }
        return rows.map {
            LongbridgeQuotePackage(
                key: $0.key,
                name: $0.name,
                description: $0.description,
                startAt: $0.startAt > 0
                    ? Date(timeIntervalSince1970: TimeInterval($0.startAt))
                    : nil,
                endAt: $0.endAt > 0
                    ? Date(timeIntervalSince1970: TimeInterval($0.endAt))
                    : nil
            )
        }
    }

    private func logQuoteFreshness(_ quotes: [Quote], receivedAt: Date) {
        for (market, rows) in Dictionary(grouping: quotes, by: \.symbol.market) {
            guard !rows.isEmpty else { continue }
            let ages = rows.map { max(0, Int(receivedAt.timeIntervalSince($0.timestamp))) }
            let minimumAge = ages.min() ?? 0
            let maximumAge = ages.max() ?? 0
            let effectiveDelay = Int(rows.compactMap(\.sourceDelay).max() ?? 0)
            let packageDelay = Int(rows.compactMap {
                LongbridgeQuoteFreshness.packageDelay(
                    for: $0.symbol,
                    packages: negotiatedQuotePackages,
                    at: receivedAt
                )
            }.max() ?? 0)
            let signature = "\(minimumAge / 60):\(maximumAge / 60):\(effectiveDelay):\(packageDelay)"
            let previous = freshnessLogState[market]
            guard previous?.signature != signature
                    || receivedAt.timeIntervalSince(previous?.loggedAt ?? .distantPast) >= 5 * 60 else {
                continue
            }
            freshnessLogState[market] = FreshnessLogState(
                signature: signature,
                loggedAt: receivedAt
            )
            longbridgeLogger.info(
                "Quote freshness market=\(market.rawValue, privacy: .public) count=\(rows.count, privacy: .public) ageSeconds=\(minimumAge, privacy: .public)-\(maximumAge, privacy: .public) packageDelaySeconds=\(packageDelay, privacy: .public) effectiveDelaySeconds=\(effectiveDelay, privacy: .public)"
            )
        }
    }

    private static func withCStringArray<Result>(
        _ strings: [String],
        _ body: (UnsafePointer<UnsafePointer<CChar>?>?, UInt) throws -> Result
    ) rethrows -> Result {
        let storage = strings.map { strdup($0) }
        defer {
            for pointer in storage {
                free(pointer)
            }
        }
        let pointers: [UnsafePointer<CChar>?] = storage.map { pointer in
            guard let pointer else { return nil }
            return UnsafePointer(pointer)
        }
        return try pointers.withUnsafeBufferPointer { buffer in
            try body(buffer.baseAddress, UInt(buffer.count))
        }
    }

    private static func sdkPeriod(_ period: CandlePeriod) -> Int32 {
        switch period {
        case .minute1: 1
        case .minute5: 4
        case .minute15: 6
        case .minute30: 8
        case .hour1: 10
        case .day: 14
        case .week: 15
        case .month: 16
        }
    }

    private static func candles(from rows: [LBSDKCandlestick]) -> [Candle] {
        rows.compactMap { row in
            guard let close = row.close,
                  let open = row.open,
                  let low = row.low,
                  let high = row.high else { return nil }
            return Candle(
                time: Date(timeIntervalSince1970: TimeInterval(row.timestamp)),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: Double(row.volume)
            )
        }
    }

    private static func sdkDateTime(for date: Date, market: Market) -> lb_datetime_t {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return lb_datetime_t(
            date: lb_date_t(
                year: Int32(components.year ?? 1970),
                month: UInt8(components.month ?? 1),
                day: UInt8(components.day ?? 1)
            ),
            time: lb_time_t(
                hour: UInt8(components.hour ?? 0),
                minute: UInt8(components.minute ?? 0),
                second: UInt8(components.second ?? 0)
            )
        )
    }

    private static func quote(
        from snapshot: LBSDKSecurityQuote,
        symbol: SymbolID,
        packages: [LongbridgeQuotePackage],
        receivedAt: Date
    ) -> Quote? {
        guard let regularPrice = snapshot.lastDone,
              let previousClose = snapshot.previousClose else { return nil }

        var price = regularPrice
        var reference = previousClose
        var marketState: MarketState = .regular
        var timestamp = snapshot.timestamp

        if symbol.market == .us {
            let session: (LBSDKPrePostQuote?, MarketState)? =
                switch TradingCalendar.state(of: .us) {
                case .preMarket: (snapshot.preMarket, .preMarket)
                case .postMarket: (snapshot.postMarket, .postMarket)
                case .overnight: (snapshot.overnight, .overnight)
                case .closed: (snapshot.overnight, .overnight)
                default: nil
                }
            if let session,
               let sessionQuote = session.0,
               let sessionPrice = sessionQuote.lastDone,
               sessionQuote.timestamp >= snapshot.timestamp {
                price = sessionPrice
                reference = sessionQuote.previousClose ?? regularPrice
                marketState = session.1
                timestamp = sessionQuote.timestamp
            }
        }

        return Quote(
            symbol: symbol,
            price: price,
            previousClose: reference,
            open: snapshot.open,
            high: snapshot.high,
            low: snapshot.low,
            volume: Double(snapshot.volume),
            turnover: snapshot.turnover,
            currencyCode: symbol.market.currencyCode,
            sourceDelay: LongbridgeQuoteFreshness.effectiveDelay(
                for: symbol,
                timestamp: timestamp > 0
                    ? Date(timeIntervalSince1970: TimeInterval(timestamp))
                    : receivedAt,
                packages: packages,
                receivedAt: receivedAt
            ),
            timestamp: timestamp > 0
                ? Date(timeIntervalSince1970: TimeInterval(timestamp))
                : receivedAt,
            marketState: marketState
        )
    }

    private static func preferredName(
        from snapshot: LBSDKSecurityName,
        localeIdentifier: String
    ) -> String? {
        let candidates: [String]
        if localeIdentifier.hasPrefix("zh-Hant") || localeIdentifier.hasPrefix("zh-HK") {
            candidates = [snapshot.nameHK, snapshot.nameCN, snapshot.nameEN]
        } else if localeIdentifier.hasPrefix("zh") {
            candidates = [snapshot.nameCN, snapshot.nameHK, snapshot.nameEN]
        } else {
            candidates = [snapshot.nameEN, snapshot.nameCN, snapshot.nameHK]
        }
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func marketState(forTradeSession session: Int32) -> MarketState {
        switch session {
        case 1: .preMarket
        case 2: .postMarket
        case 3: .overnight
        default: .regular
        }
    }

    private static func connectionIssue(for error: any Error) -> LongbridgeConnectionIssue {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .rateLimited:
                return .rateLimited
            case .clientError:
                return .authentication
            case .network:
                return .network
            case .badResponse:
                return .server
            case .unsupported, .symbolNotFound:
                return .server
            }
        }
        let detail = String(describing: error).lowercased()
        if detail.contains("limit") { return .connectionLimit }
        if detail.contains("auth") || detail.contains("token") { return .authentication }
        if detail.contains("network") || detail.contains("socket") { return .network }
        return .server
    }

    private static func issueLabel(for error: any Error) -> String {
        switch connectionIssue(for: error) {
        case .connectionLimit: "connection-limit"
        case .authentication: "authentication"
        case .rateLimited: "rate-limited"
        case .network: "network"
        case .server: "server"
        }
    }

    private static func fingerprint(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func statusLabel(_ status: LongbridgeConnectionStatus) -> String {
        switch status {
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .reconnecting: "reconnecting"
        case .connected: "connected"
        case .failed(let issue):
            switch issue {
            case .connectionLimit: "failed.connection-limit"
            case .authentication: "failed.authentication"
            case .rateLimited: "failed.rate-limited"
            case .network: "failed.network"
            case .server: "failed.server"
            }
        }
    }
}

enum LongbridgeMinuteCandleBackfill {
    static let apiPageLimit = 1_000

    /// The extra page is only needed when the latest page is full and its oldest row
    /// has already cut into a session some chart still displays: the extended chart's
    /// 04:00–20:00 frame, or — during the overnight/pre-market stretch — the PRIOR
    /// day's regular session, which the regular-mode sparkline keeps showing while
    /// "All sessions" rows (overnight + pre alone can be 800) crowd it out of the page.
    static func needsOlderPage(
        _ latest: [Candle],
        market: Market,
        period: CandlePeriod,
        latestPageReachedLimit: Bool
    ) -> Bool {
        guard market == .us,
              period == .minute1,
              latestPageReachedLimit,
              let earliest = latest.min(by: { $0.time < $1.time }) else {
            return false
        }
        let extended = IntradayTrendSnapshot(
            candles: latest,
            market: market,
            includesExtendedHours: true
        )
        guard let preOpen = extended.session.preOpen else { return false }
        if extended.session.contains(earliest.time),
           earliest.time > preOpen.addingTimeInterval(60) {
            return true
        }
        let regular = IntradayTrendSnapshot(candles: latest, market: market)
        return earliest.time > regular.session.open.addingTimeInterval(60)
    }

    static func merge(
        older: [Candle],
        latest: [Candle],
        limit: Int
    ) -> [Candle] {
        var byTime: [Date: Candle] = [:]
        byTime.reserveCapacity(older.count + latest.count)
        for candle in older { byTime[candle.time] = candle }
        // Prefer the latest-page value when the offset endpoint repeats its boundary row.
        for candle in latest { byTime[candle.time] = candle }
        return Array(byTime.values.sorted { $0.time < $1.time }.suffix(max(1, limit)))
    }
}
#endif
