import Foundation

struct BinanceExchangeInfoResponse: Decodable, Sendable {
    let symbols: [BinanceExchangeSymbol]
}

struct BinanceExchangeSymbol: Codable, Hashable, Sendable {
    let symbol: String
    let status: String
    let baseAsset: String
    let quoteAsset: String

    var pair: CryptoPair {
        CryptoPair(baseAsset: baseAsset, quoteAsset: quoteAsset)
    }
}

actor BinanceSymbolCatalog {
    struct Snapshot: Codable, Sendable {
        let fetchedAt: Date
        let symbols: [BinanceExchangeSymbol]
    }

    typealias Fetcher = @Sendable () async throws -> [BinanceExchangeSymbol]

    static let defaultTTL: TimeInterval = 24 * 60 * 60
    static let missRefreshInterval: TimeInterval = 60 * 60

    private let cacheURL: URL?
    private let ttl: TimeInterval
    private let fetcher: Fetcher
    private var snapshot: Snapshot?
    private var didLoadCache = false
    private var refreshTask: Task<Snapshot, any Error>?

    init(cacheURL: URL?, ttl: TimeInterval = defaultTTL, fetcher: @escaping Fetcher) {
        self.cacheURL = cacheURL
        self.ttl = ttl
        self.fetcher = fetcher
    }

    static func defaultCacheURL(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pulse", isDirectory: true)
            .appendingPathComponent("binance-symbol-catalog-v1.json")
    }

    /// Used on app launch. A fresh disk snapshot returns immediately; stale or missing
    /// data is refreshed without blocking the rest of AppState initialization.
    func refreshIfNeeded(now: Date = .now) async throws {
        loadCacheIfNeeded()
        guard snapshot.map({ now.timeIntervalSince($0.fetchedAt) >= ttl }) ?? true else { return }
        try await refresh(now: now)
    }

    func refreshAfterSymbolFailure(now: Date = .now) async {
        loadCacheIfNeeded()
        guard snapshot.map({ now.timeIntervalSince($0.fetchedAt) >= Self.missRefreshInterval }) ?? true else {
            return
        }
        try? await refresh(now: now)
    }

    func search(_ rawQuery: String, limit: Int = 20, now: Date = .now) async throws -> [SymbolInfo] {
        loadCacheIfNeeded()
        if snapshot == nil {
            try await refresh(now: now)
        } else if let snapshot, now.timeIntervalSince(snapshot.fetchedAt) >= ttl {
            // Stale-while-revalidate: searching remains instant while a fresh directory
            // is fetched in the background.
            Task { try? await self.refresh(now: now) }
        }

        var results = rankedResults(for: rawQuery, limit: limit)
        if results.isEmpty,
           snapshot.map({ now.timeIntervalSince($0.fetchedAt) >= Self.missRefreshInterval }) ?? true {
            try? await refresh(now: now)
            results = rankedResults(for: rawQuery, limit: limit)
        }
        return results
    }

    private func refresh(now: Date) async throws {
        if let refreshTask {
            snapshot = try await cancellableValue(of: refreshTask)
            return
        }

        let fetcher = self.fetcher
        let task = Task<Snapshot, any Error> {
            let symbols = try await fetcher()
            return Snapshot(
                fetchedAt: now,
                symbols: symbols.filter { $0.status == "TRADING" }
            )
        }
        refreshTask = task
        do {
            let fresh = try await cancellableValue(of: task)
            snapshot = fresh
            refreshTask = nil
            persist(fresh)
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func cancellableValue(of task: Task<Snapshot, any Error>) async throws -> Snapshot {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func loadCacheIfNeeded() {
        guard !didLoadCache else { return }
        didLoadCache = true
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snapshot = cached
    }

    private func persist(_ snapshot: Snapshot) {
        guard let cacheURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // The directory is an optimization. Search remains available from memory when
            // a sandbox or filesystem policy prevents persistence.
        }
    }

    private func rankedResults(for rawQuery: String, limit: Int) -> [SymbolInfo] {
        let query = Self.normalizedQuery(rawQuery)
        guard !query.isEmpty, let snapshot else { return [] }

        return snapshot.symbols.compactMap { entry -> (Int, Int, BinanceExchangeSymbol)? in
            let symbol = entry.symbol.uppercased()
            let base = entry.baseAsset.uppercased()
            let quote = entry.quoteAsset.uppercased()
            let score: Int
            if symbol == query {
                score = 0
            } else if base == query {
                score = 1
            } else if symbol.hasPrefix(query) {
                score = 2
            } else if base.hasPrefix(query) {
                score = 3
            } else if symbol.contains(query) || quote == query {
                score = 4
            } else {
                return nil
            }
            return (score, Self.quotePriority(quote), entry)
        }
        .sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2.symbol < $1.2.symbol
        }
        .prefix(max(0, limit))
        .map { result in
            let entry = result.2
            return SymbolInfo(
                symbol: SymbolID(cryptoPair: entry.pair),
                name: entry.baseAsset,
                exchangeName: "Binance Spot",
                type: .crypto
            )
        }
    }

    private static func normalizedQuery(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func quotePriority(_ quote: String) -> Int {
        switch quote {
        case "USDT": 0
        case "USDC": 1
        case "FDUSD": 2
        case "BTC": 3
        case "ETH": 4
        default: 10
        }
    }
}
