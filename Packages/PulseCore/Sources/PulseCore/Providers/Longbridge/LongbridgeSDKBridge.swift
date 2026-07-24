#if os(macOS)
import Darwin
import Foundation
import LongbridgeCABI

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
    typealias ConfigFree = @convention(c) (OpaquePointer?) -> Void
    typealias ContextNew = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias ContextRelease = @convention(c) (OpaquePointer?) -> Void
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
    typealias DecimalToDouble = @convention(c) (OpaquePointer?) -> Double
    typealias ErrorMessage = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    typealias ErrorCode = @convention(c) (OpaquePointer?) -> Int64

    let handle: UnsafeMutableRawPointer
    let configFromAPIKey: ConfigFromAPIKey
    let configFromOAuthToken: ConfigFromOAuthToken
    let enableOvernight: ConfigMutation
    let disablePrintQuotePackages: ConfigMutation
    let configFree: ConfigFree
    let contextNew: ContextNew
    let contextRelease: ContextRelease
    let setOnQuote: SetOnQuote
    let staticInfo: SymbolsRequest
    let quote: SymbolsRequest
    let subscribe: SubscriptionRequest
    let unsubscribe: SubscriptionRequest
    let candlesticks: CandlesticksRequest
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
        self.configFree = try Self.resolve(handle, "lb_config_free", as: ConfigFree.self)
        self.contextNew = try Self.resolve(handle, "lb_quote_context_new", as: ContextNew.self)
        self.contextRelease = try Self.resolve(
            handle,
            "lb_quote_context_release",
            as: ContextRelease.self
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

    private var auth: LongbridgeAuth?
    private var library: LongbridgeSDKDynamicLibrary?
    private var context: OpaquePointer?
    private var status: LongbridgeConnectionStatus = .disconnected
    private var statusContinuation: AsyncStream<LongbridgeConnectionStatus>.Continuation?
    private var streamSubscribers: [UUID: StreamSubscriber] = [:]
    private var subscribedSymbols: Set<String> = []
    private var streamBase: [String: Quote] = [:]

    init(auth: LongbridgeAuth?) {
        self.auth = auth
    }

    func updateAuth(_ auth: LongbridgeAuth?) {
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
        finishStreams()
        releaseContext()
        setStatus(.disconnected)
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
            let symbolsBySDKName = Dictionary(uniqueKeysWithValues: mapped.map { ($0.1, $0.0) })
            let quotes = snapshots.compactMap { snapshot -> Quote? in
                guard let symbol = symbolsBySDKName[snapshot.symbol] else { return nil }
                return Self.quote(from: snapshot, symbol: symbol)
            }
            for quote in quotes {
                if let sdkSymbol = LongbridgeProvider.longbridgeSymbol(for: quote.symbol) {
                    streamBase[sdkSymbol] = quote
                }
            }
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

        do {
            let context = try await ensureContext()
            let library = try requireLibrary()
            let snapshots: [LBSDKCandlestick] = try await perform(library: library) { callback, userdata in
                sdkSymbol.withCString { symbolPointer in
                    library.candlesticks(
                        context,
                        symbolPointer,
                        sdkPeriod,
                        UInt(max(1, count)),
                        0,
                        0,
                        callback,
                        userdata
                    )
                }
            } decode: { result in
                library.copyCandlesticks(result)
            }
            let candles = snapshots.compactMap { row -> Candle? in
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
            setStatus(.connected)
            return candles
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
        quote.marketState = Self.marketState(forTradeSession: push.tradeSession)
        streamBase[push.symbol] = quote
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
        switch auth {
        case .apiKey(let credentials):
            config = credentials.appKey.withCString { appKey in
                credentials.appSecret.withCString { appSecret in
                    credentials.accessToken.withCString { accessToken in
                        library.configFromAPIKey(appKey, appSecret, accessToken)
                    }
                }
            }
        case .oauth(let session):
            let accessToken = try await session.accessTokenForSDK()
            config = accessToken.withCString { library.configFromOAuthToken($0) }
        }
        guard let config else {
            throw LongbridgeError.socket("Longbridge SDK could not create an authenticated config")
        }
        defer { library.configFree(config) }

        library.enableOvernight(config)
        library.disablePrintQuotePackages(config)
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
        return context
    }

    private func releaseContext() {
        if let context, let library {
            library.contextRelease(context)
        }
        context = nil
        subscribedSymbols = []
        streamBase = [:]
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
        statusContinuation?.yield(newStatus)
    }

    private func recordFailure(_ error: any Error) {
        if LongbridgeSDKErrorClassifier.isInvalidSymbol(error) {
            if context != nil { setStatus(.connected) }
            return
        }
        setStatus(.failed(Self.connectionIssue(for: error)))
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
        case .day: 14
        case .week: 15
        case .month: 16
        }
    }

    private static func quote(from snapshot: LBSDKSecurityQuote, symbol: SymbolID) -> Quote? {
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
            timestamp: timestamp > 0
                ? Date(timeIntervalSince1970: TimeInterval(timestamp))
                : .now,
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
}
#endif
