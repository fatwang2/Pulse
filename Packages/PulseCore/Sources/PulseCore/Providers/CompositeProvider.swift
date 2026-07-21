import Foundation

/// Routing + failover: dispatches each request, keyed by capability x market, to the first healthy provider in registration order.
/// On failure it trips that provider's circuit breaker for a while and falls back to the next one. The core and the UI only ever talk to this type.
public actor CompositeProvider: QuoteProvider {
    private let providers: [any QuoteProvider]
    private var unhealthyUntil: [String: Date] = [:]
    private var lastProviderRequestAt: [String: Date] = [:]
    private var searchCache: [String: CacheEntry<[SymbolInfo]>] = [:]
    private var quoteCache: [SymbolID: CacheEntry<Quote>] = [:]
    private var candleCache: [ProviderCandleCacheKey: CacheEntry<[Candle]>] = [:]
    private var disabledIDs: Set<String>
    private let cooldown: TimeInterval
    private let searchCacheTTL: TimeInterval
    private let quoteCacheTTL: TimeInterval
    private let candleCacheTTL: TimeInterval
    private let searchResultSettleDelay: Duration
    private let searchDeadline: Duration

    public init(providers: [any QuoteProvider],
                disabledIDs: Set<String> = [],
                cooldown: TimeInterval = 120,
                searchCacheTTL: TimeInterval = 300,
                quoteCacheTTL: TimeInterval = 12,
                candleCacheTTL: TimeInterval = 60,
                searchResultSettleDelay: Duration = .milliseconds(350),
                searchDeadline: Duration = .seconds(3)) {
        self.providers = providers
        self.disabledIDs = disabledIDs
        self.cooldown = cooldown
        self.searchCacheTTL = searchCacheTTL
        self.quoteCacheTTL = quoteCacheTTL
        self.candleCacheTTL = candleCacheTTL
        self.searchResultSettleDelay = searchResultSettleDelay
        self.searchDeadline = searchDeadline
    }

    /// Descriptors of all registered providers (including disabled ones), for display on the settings page
    public nonisolated var registeredDescriptors: [ProviderDescriptor] {
        providers.map(\.descriptor)
    }

    /// Lets the user toggle data sources in settings
    public func setDisabled(_ ids: Set<String>) {
        disabledIDs = ids
    }

    /// User-initiated retries should not remain trapped behind a previous circuit-breaker
    /// cooldown. The next request re-evaluates the provider immediately.
    public func resetHealth(_ providerID: String) {
        unhealthyUntil[providerID] = nil
    }

    public nonisolated var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: "composite",
            name: PulseLocalization.localizedString("provider.composite"),
            markets: Set(providers.flatMap { $0.descriptor.markets }),
            capabilities: Set(providers.flatMap { $0.descriptor.capabilities })
        )
    }

    // MARK: - Routing

    private func candidates(_ capability: Capability, market: Market) -> [any QuoteProvider] {
        providers.filter { provider in
            let id = provider.descriptor.id
            return provider.descriptor.supports(capability, in: market)
                && !disabledIDs.contains(id) && isHealthy(id)
        }
    }

    private func isHealthy(_ id: String) -> Bool {
        guard let until = unhealthyUntil[id] else { return true }
        if until < .now {
            unhealthyUntil[id] = nil
            return true
        }
        return false
    }

    private func markUnhealthy(_ id: String, cooldown: TimeInterval) {
        unhealthyUntil[id] = Date.now.addingTimeInterval(cooldown)
    }

    private func waitForProviderBudget(_ provider: any QuoteProvider) async throws {
        guard let minInterval = provider.descriptor.rateLimit?.minInterval, minInterval > 0 else { return }
        let id = provider.descriptor.id

        // Reserve the budget only when the request is actually ready to start.
        // A cancelled search must not leave a future reservation behind and push
        // every subsequent keystroke farther into a throttling queue.
        while true {
            try Task.checkCancellation()
            let now = Date.now
            let earliestStart = (lastProviderRequestAt[id] ?? .distantPast)
                .addingTimeInterval(minInterval)
            let delay = earliestStart.timeIntervalSince(now)
            guard delay > 0 else {
                lastProviderRequestAt[id] = now
                return
            }
            try await Task.sleep(for: .seconds(delay))
        }
    }

    private func cachedQuote(for symbol: SymbolID, maxAge: TimeInterval) -> Quote? {
        guard let entry = quoteCache[symbol], entry.isFresh(maxAge: maxAge) else { return nil }
        return entry.value
    }

    private func cachedCandles(for key: ProviderCandleCacheKey, maxAge: TimeInterval) -> [Candle]? {
        guard let entry = candleCache[key], entry.isFresh(maxAge: maxAge) else { return nil }
        return entry.value
    }

    private func preferredQuoteProvider(for market: Market, among providers: [any QuoteProvider]) -> (any QuoteProvider)? {
        // Binance is the sole crypto source. A USD Yahoo instrument is not a valid
        // substitute for a USDT Binance pair, even when their prices are close.
        if market == .crypto,
           let binance = providers.first(where: { $0.descriptor.id == BinanceProvider.providerID }) {
            return binance
        }
        // A user-keyed real-time source outranks the free delayed feeds whenever it is available.
        if let longbridge = providers.first(where: { $0.descriptor.id == LongbridgeProvider.providerID }) {
            return longbridge
        }
        if market == .us, let yahoo = providers.first(where: { $0.descriptor.id == "yahoo" }) {
            return yahoo
        }
        return providers.first
    }

    /// Only infrastructure-level errors (network down / 5xx / rate limiting) trip the circuit breaker;
    /// request-level errors (4xx, symbol not found) don't indicate a source failure and never trip it.
    /// Rate limiting gets a short cooldown (recovers quickly); network/5xx errors get the long one.
    private func noteFailure(_ id: String, _ error: any Error) {
        guard ProviderError.shouldTrip(error) else { return }
        if case ProviderError.rateLimited = error {
            markUnhealthy(id, cooldown: min(30, cooldown))
        } else {
            markUnhealthy(id, cooldown: cooldown)
        }
    }

    /// Preferred-provider grouping for a symbol set, before failover. The refresh engine
    /// uses it to poll each group at its source's own cadence; symbols with no available
    /// candidate are omitted.
    public func quoteRouting(for symbols: [SymbolID]) -> [String: [SymbolID]] {
        var groups: [String: [SymbolID]] = [:]
        for symbol in symbols {
            guard let primary = preferredQuoteProvider(
                for: symbol.market,
                among: candidates(.quotes, market: symbol.market)
            ) else { continue }
            groups[primary.descriptor.id, default: []].append(symbol)
        }
        return groups
    }

    /// Current health status of each data source (for debugging / the settings page)
    public func healthReport() -> [String: String] {
        var report: [String: String] = [:]
        for provider in providers {
            let id = provider.descriptor.id
            if disabledIDs.contains(id) {
                report[id] = "disabled"
            } else if let until = unhealthyUntil[id], until > .now {
                report[id] = "cooling until \(until.formatted(date: .omitted, time: .standard))"
            } else {
                report[id] = "healthy"
            }
        }
        return report
    }

    // MARK: - QuoteProvider

    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }
        var quotesBySymbol: [SymbolID: Quote] = [:]
        var missing: [SymbolID] = []
        for symbol in symbols {
            if let cached = cachedQuote(for: symbol, maxAge: quoteCacheTTL) {
                quotesBySymbol[symbol] = cached
            } else {
                missing.append(symbol)
            }
        }
        guard !missing.isEmpty else {
            return symbols.compactMap { quotesBySymbol[$0] }
        }

        // Group symbols by their preferred provider to merge batch requests as much as possible
        var groups: [String: [SymbolID]] = [:]
        var providerByID: [String: any QuoteProvider] = [:]
        for symbol in missing {
            guard let primary = preferredQuoteProvider(
                for: symbol.market,
                among: candidates(.quotes, market: symbol.market)
            ) else { continue }
            let id = primary.descriptor.id
            groups[id, default: []].append(symbol)
            providerByID[id] = primary
        }

        var result: [Quote] = []
        var lastError: (any Error)?
        for (id, group) in groups {
            do {
                let provider = providerByID[id]!
                try await waitForProviderBudget(provider)
                let quotes = try await provider.quotes(for: group).map { $0.sourced(by: provider.descriptor) }
                for quote in quotes {
                    quoteCache[quote.symbol] = CacheEntry(value: quote)
                    quotesBySymbol[quote.symbol] = quote
                }
                result += quotes
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                noteFailure(id, error)
                lastError = error
                // Fall back per market to the next available provider for this group
                for (market, marketSymbols) in Dictionary(grouping: group, by: \.market) {
                    guard let fallback = candidates(.quotes, market: market)
                        .first(where: { $0.descriptor.id != id }) else { continue }
                    if let recovered = try? await fallbackQuotes(
                        from: fallback,
                        for: marketSymbols
                    ) {
                        for quote in recovered {
                            quoteCache[quote.symbol] = CacheEntry(value: quote)
                            quotesBySymbol[quote.symbol] = quote
                        }
                        result += recovered
                    }
                }
            }
        }
        for symbol in missing where quotesBySymbol[symbol] == nil {
            quotesBySymbol[symbol] = quoteCache[symbol]?.value
        }
        let ordered = symbols.compactMap { quotesBySymbol[$0] }
        if ordered.isEmpty, let lastError { throw lastError }
        return ordered
    }

    private func fallbackQuotes(
        from provider: any QuoteProvider,
        for symbols: [SymbolID]
    ) async throws -> [Quote] {
        try await waitForProviderBudget(provider)
        return try await provider.quotes(for: symbols).map { $0.sourced(by: provider.descriptor) }
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        let key = ProviderCandleCacheKey(symbol: symbol, period: period, count: count)
        if let cached = cachedCandles(for: key, maxAge: candleCacheTTL) {
            return cached
        }
        let candles = try await failover(
            .candles,
            market: symbol.market,
            eligible: { $0.descriptor.supports(candles: period, in: symbol.market) }
        ) { provider in
            try await provider.candles(for: symbol, period: period, count: count)
        }
        candleCache[key] = CacheEntry(value: candles)
        return candles
    }

    /// Real-time push is routed per market and then merged. This lets Longbridge stream
    /// securities while Binance streams crypto over the same app-level subscription.
    public nonisolated func quoteStream(for symbols: [SymbolID]) -> AsyncThrowingStream<Quote, any Error>? {
        guard providers.contains(where: { $0.descriptor.capabilities.contains(.streaming) }) else {
            return nil
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                let routes = await self.streamingRoutes(for: symbols)
                guard !routes.isEmpty else {
                    continuation.finish()
                    return
                }

                await withTaskGroup(of: Void.self) { group in
                    for route in routes {
                        group.addTask {
                            guard let inner = route.provider.quoteStream(for: route.symbols) else { return }
                            do {
                                for try await quote in inner {
                                    continuation.yield(quote.sourced(by: route.provider.descriptor))
                                }
                            } catch {
                                // One market stream can disappear independently; the remaining
                                // streams keep running and REST polling continues as a fallback.
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct StreamingRoute: Sendable {
        var provider: any QuoteProvider
        var symbols: [SymbolID]
    }

    private func streamingRoutes(for symbols: [SymbolID]) -> [StreamingRoute] {
        var symbolsByProvider: [String: [SymbolID]] = [:]
        var providerByID: [String: any QuoteProvider] = [:]
        for symbol in symbols {
            let available = candidates(.streaming, market: symbol.market)
            guard let streamer = preferredQuoteProvider(for: symbol.market, among: available) else { continue }
            let id = streamer.descriptor.id
            symbolsByProvider[id, default: []].append(symbol)
            providerByID[id] = streamer
        }
        return symbolsByProvider.compactMap { id, symbols in
            providerByID[id].map { StreamingRoute(provider: $0, symbols: symbols) }
        }
    }

    public func search(_ query: String) async throws -> [SymbolInfo] {
        let cacheKey = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let entry = searchCache[cacheKey], entry.isFresh(maxAge: searchCacheTTL) {
            return entry.value
        }
        // Search is market-agnostic: query search-capable providers in registration order, then merge and dedupe.
        // (Tencent excels at Chinese / pinyin / A-share codes, Yahoo at English names / global symbols — merging gives the widest coverage.)
        let enabled = providers.filter {
            $0.descriptor.capabilities.contains(.search) && !disabledIDs.contains($0.descriptor.id)
        }
        guard !enabled.isEmpty else { throw ProviderError.unsupported(.search) }
        let capable = enabled.filter { isHealthy($0.descriptor.id) }
        // Sources exist but are all in circuit-breaker cooldown — that's not the same as disabled: report rate limiting, which recovers automatically
        guard !capable.isEmpty else { throw ProviderError.rateLimited }

        // Search providers are independent. Return soon after the first useful source,
        // while keeping a short window for other fast sources to enrich the result set.
        // A hard deadline prevents one stalled source from holding every result hostage.
        let aggregation = await withTaskGroup(
            of: SearchEvent.self,
            returning: SearchAggregation.self
        ) { group in
            for (index, provider) in capable.enumerated() {
                group.addTask {
                    do {
                        try await self.waitForProviderBudget(provider)
                        try Task.checkCancellation()
                        return .provider(index, .success(try await provider.search(query)))
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        return .provider(index, .failure(error))
                    }
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: self.searchDeadline)
                    return .hardDeadline
                } catch {
                    return .cancelled
                }
            }

            var completed: [(Int, Result<[SymbolInfo], any Error>)] = []
            var completedProviderCount = 0
            var settleTimerStarted = false
            while let event = await group.next() {
                switch event {
                case .provider(let index, let outcome):
                    completed.append((index, outcome))
                    completedProviderCount += 1

                    if !settleTimerStarted,
                       case .success(let results) = outcome,
                       !results.isEmpty {
                        settleTimerStarted = true
                        group.addTask {
                            do {
                                try await Task.sleep(for: self.searchResultSettleDelay)
                                return .settleDeadline
                            } catch {
                                return .cancelled
                            }
                        }
                    }

                    if completedProviderCount == capable.count {
                        group.cancelAll()
                        return SearchAggregation(
                            outcomes: completed.sorted { $0.0 < $1.0 },
                            completedAllProviders: true
                        )
                    }
                case .settleDeadline, .hardDeadline:
                    group.cancelAll()
                    return SearchAggregation(
                        outcomes: completed.sorted { $0.0 < $1.0 },
                        completedAllProviders: false
                    )
                case .cancelled:
                    continue
                }
            }
            group.cancelAll()
            return SearchAggregation(
                outcomes: completed.sorted { $0.0 < $1.0 },
                completedAllProviders: false
            )
        }
        try Task.checkCancellation()

        var merged: [SymbolInfo] = []
        var indexBySymbol: [SymbolID: Int] = [:]
        var lastError: (any Error)?
        for (index, outcome) in aggregation.outcomes {
            switch outcome {
            case .success(let infos):
                for info in infos {
                    if let existingIndex = indexBySymbol[info.symbol] {
                        let existing = merged[existingIndex]
                        if Self.isPlaceholderName(existing.name, for: existing.symbol),
                           !Self.isPlaceholderName(info.name, for: info.symbol) {
                            merged[existingIndex].name = info.name
                        }
                    } else {
                        indexBySymbol[info.symbol] = merged.count
                        merged.append(info)
                    }
                }
            case .failure(let error):
                noteFailure(capable[index].descriptor.id, error)
                lastError = error
            }
        }
        if merged.isEmpty {
            if let lastError,
               aggregation.outcomes.allSatisfy({ if case .failure = $0.1 { true } else { false } }) {
                throw lastError
            }
            if !aggregation.completedAllProviders {
                throw lastError ?? ProviderError.network(underlying: "Search timed out")
            }
        }

        // Cache only a complete, fully successful answer. Partial results are useful
        // for the current interaction but should not mask a recovered source later.
        let allProvidersSucceeded = aggregation.completedAllProviders
            && aggregation.outcomes.allSatisfy { if case .success = $0.1 { true } else { false } }
        if allProvidersSucceeded {
            searchCache[cacheKey] = CacheEntry(value: merged)
        }
        return merged
    }

    private enum SearchEvent: Sendable {
        case provider(Int, Result<[SymbolInfo], any Error>)
        case settleDeadline
        case hardDeadline
        case cancelled
    }

    private struct SearchAggregation: Sendable {
        var outcomes: [(Int, Result<[SymbolInfo], any Error>)]
        var completedAllProviders: Bool
    }

    private nonisolated static func isPlaceholderName(_ name: String, for symbol: SymbolID) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized == symbol.code.uppercased()
            || normalized == symbol.displayCode.uppercased()
            || normalized == symbol.cryptoPair?.baseAsset
    }

    private func failover<T>(_ capability: Capability, market: Market,
                             eligible: (any QuoteProvider) -> Bool = { _ in true },
                             _ operation: (any QuoteProvider) async throws -> T) async throws -> T {
        let enabled = providers.filter {
            $0.descriptor.supports(capability, in: market)
                && eligible($0)
                && !disabledIDs.contains($0.descriptor.id)
        }
        guard !enabled.isEmpty else { throw ProviderError.unsupported(capability) }
        let healthy = enabled.filter { isHealthy($0.descriptor.id) }
        guard !healthy.isEmpty else { throw ProviderError.rateLimited }  // All in cooldown; recovers automatically shortly

        var lastError: (any Error) = ProviderError.unsupported(capability)
        for provider in healthy {
            do {
                try await waitForProviderBudget(provider)
                return try await operation(provider)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                noteFailure(provider.descriptor.id, error)
                lastError = error
            }
        }
        throw lastError
    }
}

private struct CacheEntry<Value> {
    var value: Value
    var storedAt: Date = .now

    func isFresh(maxAge: TimeInterval) -> Bool {
        Date.now.timeIntervalSince(storedAt) <= maxAge
    }
}

private struct ProviderCandleCacheKey: Hashable {
    var symbol: SymbolID
    var period: CandlePeriod
    var count: Int
}
