import Foundation

/// Routing + failover: dispatches each request, keyed by capability x market, to the first healthy provider in registration order.
/// On failure it trips that provider's circuit breaker for a while and falls back to the next one. The core and the UI only ever talk to this type.
public actor CompositeProvider: QuoteProvider {
    private let providers: [any QuoteProvider]
    private var unhealthyUntil: [String: Date] = [:]
    private var nextProviderRequestAt: [String: Date] = [:]
    private var searchCache: [String: CacheEntry<[SymbolInfo]>] = [:]
    private var quoteCache: [SymbolID: CacheEntry<Quote>] = [:]
    private var candleCache: [ProviderCandleCacheKey: CacheEntry<[Candle]>] = [:]
    private var disabledIDs: Set<String>
    private let cooldown: TimeInterval
    private let searchCacheTTL: TimeInterval
    private let quoteCacheTTL: TimeInterval
    private let candleCacheTTL: TimeInterval

    public init(providers: [any QuoteProvider],
                disabledIDs: Set<String> = [],
                cooldown: TimeInterval = 120,
                searchCacheTTL: TimeInterval = 300,
                quoteCacheTTL: TimeInterval = 12,
                candleCacheTTL: TimeInterval = 60) {
        self.providers = providers
        self.disabledIDs = disabledIDs
        self.cooldown = cooldown
        self.searchCacheTTL = searchCacheTTL
        self.quoteCacheTTL = quoteCacheTTL
        self.candleCacheTTL = candleCacheTTL
    }

    /// Descriptors of all registered providers (including disabled ones), for display on the settings page
    public nonisolated var registeredDescriptors: [ProviderDescriptor] {
        providers.map(\.descriptor)
    }

    /// Lets the user toggle data sources in settings
    public func setDisabled(_ ids: Set<String>) {
        disabledIDs = ids
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

    private func waitForProviderBudget(_ provider: any QuoteProvider) async {
        guard let minInterval = provider.descriptor.rateLimit?.minInterval, minInterval > 0 else { return }
        let id = provider.descriptor.id
        let now = Date.now
        let scheduledAt = max(now, nextProviderRequestAt[id] ?? .distantPast)
        nextProviderRequestAt[id] = scheduledAt.addingTimeInterval(minInterval)
        let delay = scheduledAt.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
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
                await waitForProviderBudget(provider)
                let quotes = try await provider.quotes(for: group).map { $0.sourced(by: provider.descriptor) }
                for quote in quotes {
                    quoteCache[quote.symbol] = CacheEntry(value: quote)
                    quotesBySymbol[quote.symbol] = quote
                }
                result += quotes
            } catch {
                noteFailure(id, error)
                lastError = error
                // Fall back per market to the next available provider for this group
                for (market, marketSymbols) in Dictionary(grouping: group, by: \.market) {
                    guard let fallback = candidates(.quotes, market: market)
                        .first(where: { $0.descriptor.id != id }) else { continue }
                    await waitForProviderBudget(fallback)
                    if let recovered = try? await fallback.quotes(for: marketSymbols).map({ $0.sourced(by: fallback.descriptor) }) {
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

        var outcomes: [(Int, Result<[SymbolInfo], any Error>)] = []
        for (index, provider) in capable.enumerated() {
            await waitForProviderBudget(provider)
            do {
                outcomes.append((index, .success(try await provider.search(query))))
            } catch {
                outcomes.append((index, .failure(error)))
            }
        }

        var merged: [SymbolInfo] = []
        var seen = Set<SymbolID>()
        var lastError: (any Error)?
        for (index, outcome) in outcomes {
            switch outcome {
            case .success(let infos):
                for info in infos where seen.insert(info.symbol).inserted {
                    merged.append(info)
                }
            case .failure(let error):
                noteFailure(capable[index].descriptor.id, error)
                lastError = error
            }
        }
        // Only throw when every provider failed; partial failures with results still return normally
        if merged.isEmpty, let lastError, outcomes.allSatisfy({ if case .failure = $0.1 { true } else { false } }) {
            throw lastError
        }
        searchCache[cacheKey] = CacheEntry(value: merged)
        return merged
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
                await waitForProviderBudget(provider)
                return try await operation(provider)
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
