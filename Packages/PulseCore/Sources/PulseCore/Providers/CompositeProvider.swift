import Foundation

/// Routing + failover: dispatches each request, keyed by capability x market, to the first healthy provider in registration order.
/// On failure it trips that provider's circuit breaker for a while and falls back to the next one. The core and the UI only ever talk to this type.
public actor CompositeProvider: QuoteProvider {
    private let providers: [any QuoteProvider]
    private var unhealthyUntil: [String: Date] = [:]
    private var disabledIDs: Set<String>
    private let cooldown: TimeInterval

    public init(providers: [any QuoteProvider], disabledIDs: Set<String> = [], cooldown: TimeInterval = 120) {
        self.providers = providers
        self.disabledIDs = disabledIDs
        self.cooldown = cooldown
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
            name: "Pulse 聚合",
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

        // Group symbols by their preferred provider to merge batch requests as much as possible
        var groups: [String: [SymbolID]] = [:]
        var providerByID: [String: any QuoteProvider] = [:]
        for symbol in symbols {
            guard let primary = candidates(.quotes, market: symbol.market).first else { continue }
            let id = primary.descriptor.id
            groups[id, default: []].append(symbol)
            providerByID[id] = primary
        }

        var result: [Quote] = []
        var lastError: (any Error)?
        for (id, group) in groups {
            do {
                result += try await providerByID[id]!.quotes(for: group)
            } catch {
                noteFailure(id, error)
                lastError = error
                // Fall back per market to the next available provider for this group
                for (market, marketSymbols) in Dictionary(grouping: group, by: \.market) {
                    guard let fallback = candidates(.quotes, market: market)
                        .first(where: { $0.descriptor.id != id }) else { continue }
                    if let recovered = try? await fallback.quotes(for: marketSymbols) {
                        result += recovered
                    }
                }
            }
        }
        if result.isEmpty, let lastError { throw lastError }
        return result
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        try await failover(.candles, market: symbol.market) { provider in
            try await provider.candles(for: symbol, period: period, count: count)
        }
    }

    public func search(_ query: String) async throws -> [SymbolInfo] {
        // Search is market-agnostic: query all search-capable providers concurrently, then merge and dedupe in registration order.
        // (Tencent excels at Chinese / pinyin / A-share codes, Yahoo at English names / global symbols — merging gives the widest coverage.)
        let enabled = providers.filter {
            $0.descriptor.capabilities.contains(.search) && !disabledIDs.contains($0.descriptor.id)
        }
        guard !enabled.isEmpty else { throw ProviderError.unsupported(.search) }
        let capable = enabled.filter { isHealthy($0.descriptor.id) }
        // Sources exist but are all in circuit-breaker cooldown — that's not the same as disabled: report rate limiting, which recovers automatically
        guard !capable.isEmpty else { throw ProviderError.rateLimited }

        let outcomes = await withTaskGroup(of: (Int, Result<[SymbolInfo], any Error>).self) { group in
            for (index, provider) in capable.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await provider.search(query)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<[SymbolInfo], any Error>)] = []
            for await outcome in group { collected.append(outcome) }
            return collected.sorted { $0.0 < $1.0 }
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
        return merged
    }

    private func failover<T>(_ capability: Capability, market: Market,
                             _ operation: (any QuoteProvider) async throws -> T) async throws -> T {
        let enabled = providers.filter {
            $0.descriptor.supports(capability, in: market) && !disabledIDs.contains($0.descriptor.id)
        }
        guard !enabled.isEmpty else { throw ProviderError.unsupported(capability) }
        let healthy = enabled.filter { isHealthy($0.descriptor.id) }
        guard !healthy.isEmpty else { throw ProviderError.rateLimited }  // All in cooldown; recovers automatically shortly

        var lastError: (any Error) = ProviderError.unsupported(capability)
        for provider in healthy {
            do {
                return try await operation(provider)
            } catch {
                noteFailure(provider.descriptor.id, error)
                lastError = error
            }
        }
        throw lastError
    }
}
