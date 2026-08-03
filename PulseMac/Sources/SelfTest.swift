import AppKit
import Dispatch
import Foundation
import SwiftUI
import PulseCore
import PulseUI

/// In-sandbox data pipeline self-test: `./Pulse.app/Contents/MacOS/Pulse --selftest`
/// Unlike the CLI unit tests, this runs in the app's real sandbox/signing/network environment.
enum SelfTest {
    private actor LongbridgeSDKStabilityMetrics {
        private var seedCount = 0
        private var pushCount = 0
        private var latestPushPrice: Double?
        private var streamError: String?

        func recordSeed() {
            seedCount += 1
        }

        func recordPush(_ quote: Quote) {
            pushCount += 1
            latestPushPrice = quote.price
        }

        func recordStreamError(_ error: any Error) {
            streamError = String(describing: error)
        }

        func snapshot() -> (seeds: Int, pushes: Int, latestPushPrice: Double?, streamError: String?) {
            (seedCount, pushCount, latestPushPrice, streamError)
        }
    }

    private static func longbridgeSelfTestAuth() throws -> LongbridgeAuth {
        if let tokens = LongbridgeCredentialStore.loadOAuthTokens() {
            let session = LongbridgeOAuthSession(tokens: tokens) { rotated in
                try? LongbridgeCredentialStore.saveOAuthTokens(rotated)
            }
            return .oauth(session)
        }
        if let credentials = LongbridgeCredentialStore.load(), credentials.isComplete {
            return .apiKey(credentials)
        }
        throw LongbridgeError.notConfigured
    }
    @MainActor
    static func runIfRequested() {
        if CommandLine.arguments.contains("--settings-persistence-selftest") {
            let suiteName = "app.pulse.mac.settings-persistence-selftest"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                print("PULSE_SETTINGS_PERSISTENCE_SELFTEST failed error=unable-to-create-defaults")
                fflush(stdout)
                exit(1)
            }
            defaults.removePersistentDomain(forName: suiteName)

            let configured = AppSettings(defaults: defaults)
            configured.redUp = false
            configured.watchRowMetricMode = .changePercent

            let reloaded = AppSettings(defaults: defaults)
            let passed = !reloaded.redUp && reloaded.watchRowMetricMode == .changePercent
            defaults.removePersistentDomain(forName: suiteName)

            guard passed else {
                print(
                    "PULSE_SETTINGS_PERSISTENCE_SELFTEST failed " +
                    "redUp=\(reloaded.redUp) metric=\(reloaded.watchRowMetricMode.rawValue)"
                )
                fflush(stdout)
                exit(1)
            }
            print(
                "PULSE_SETTINGS_PERSISTENCE_SELFTEST ok " +
                "redUp=false metric=changePercent"
            )
            fflush(stdout)
            exit(0)
        }

        if CommandLine.arguments.contains("--longbridge-sdk-live-selftest") {
            Task.detached {
                do {
                    let auth = try longbridgeSelfTestAuth()
                    let provider = LongbridgeProvider(auth: auth)
                    await provider.updateAuth(auth)
                    let routedProvider = CompositeProvider(
                        providers: [provider, TencentProvider(), YahooProvider()]
                    )
                    let symbols = [
                        SymbolID(market: .hk, code: "700"),
                        SymbolID(market: .sh, code: "600519"),
                        SymbolID(market: .us, code: "AAPL"),
                        SymbolID(market: .us, code: "PDD"),
                    ]
                    let quotes = try await provider.quotes(for: symbols)
                    let routedQuotes = try await routedProvider.quotes(for: symbols)
                    let quotePackages = try await provider.quotePackages()
                    let names = try await provider.securityNames(for: symbols)
                    let candles = try await provider.candles(
                        for: symbols[0],
                        period: .minute1,
                        count: 5
                    )
                    let health = await routedProvider.healthReport()
                    guard quotes.count == symbols.count,
                          routedQuotes.count == symbols.count,
                          names.count == symbols.count,
                          names.allSatisfy({ !$0.name.isEmpty }),
                          !candles.isEmpty,
                          health[LongbridgeProvider.providerID] == "healthy" else {
                        throw ProviderError.badResponse(
                            "SDK routing check failed: quotes=\(quotes.count)/\(symbols.count), " +
                            "routed=\(routedQuotes.count)/\(symbols.count), " +
                            "names=\(names.count)/\(symbols.count), " +
                            "candles=\(candles.count), sources=\(routedQuotes.compactMap(\.sourceID)), " +
                            "health=\(health)"
                        )
                    }
                    let quoteSummary = quotes
                        .map {
                            let age = max(0, Int(Date.now.timeIntervalSince($0.timestamp)))
                            let delay = Int($0.sourceDelay ?? 0)
                            return "\($0.symbol)=\(String(format: "%.4f", $0.price))" +
                                "@\(Int($0.timestamp.timeIntervalSince1970))" +
                                "/age\(age)s/delay\(delay)s"
                        }
                        .joined(separator: ",")
                    let packageSummary = quotePackages
                        .filter { !$0.key.isEmpty }
                        .map {
                            let name = $0.name.replacingOccurrences(of: " ", with: "_")
                            let description = $0.description
                                .replacingOccurrences(of: " ", with: "_")
                                .replacingOccurrences(of: "\n", with: "")
                            let start = $0.startAt.map {
                                String(Int($0.timeIntervalSince1970))
                            } ?? "none"
                            let end = $0.endAt.map {
                                String(Int($0.timeIntervalSince1970))
                            } ?? "none"
                            return "\($0.key){name=\(name),description=\(description)," +
                                "start=\(start),end=\(end)}"
                        }
                        .sorted()
                        .joined(separator: ",")
                    let nameSummary = names
                        .map { "\($0.symbol)=\($0.name)" }
                        .joined(separator: ",")
                    let routingSummary = routedQuotes
                        .map { "\($0.symbol)=\($0.sourceID ?? "none")" }
                        .joined(separator: ",")
                    print(
                        "PULSE_LONGBRIDGE_SDK_LIVE_SELFTEST ok " +
                        "transport=official-sdk-v4.4.1 quotes=\(quoteSummary) " +
                        "packages=\(packageSummary) names=\(nameSummary) candles=\(candles.count) " +
                        "routing=\(routingSummary) health=healthy"
                    )
                    fflush(stdout)
                    exit(0)
                } catch {
                    print("PULSE_LONGBRIDGE_SDK_LIVE_SELFTEST failed error=\(error)")
                    fflush(stdout)
                    exit(1)
                }
            }
            dispatchMain()
        }

        if CommandLine.arguments.contains("--longbridge-sdk-watchlist-selftest") {
            Task.detached {
                do {
                    let auth = try longbridgeSelfTestAuth()
                    let provider = LongbridgeProvider(auth: auth)
                    await provider.updateAuth(auth)
                    let routedProvider = CompositeProvider(
                        providers: [provider, TencentProvider(), YahooProvider()]
                    )

                    let storedSymbols = await MainActor.run { WatchlistStore().symbols }
                    let probes = [
                        SymbolID(index: .nasdaqComposite),
                        SymbolID(index: .dowJonesIndustrial),
                        SymbolID(index: .sp500),
                        SymbolID(index: .russell1000),
                        SymbolID(index: .hangSengTech),
                        SymbolID(index: .chiNext),
                        SymbolID(market: .us, code: "COLO"),
                        SymbolID(market: .us, code: "USO"),
                    ]
                    var symbols = storedSymbols.filter { $0.market != .crypto }
                    for symbol in probes where !symbols.contains(symbol) {
                        symbols.append(symbol)
                    }

                    let quotes = try await routedProvider.quotes(for: symbols)
                    try await provider.debugSDKSubscriptionRoundTrip(for: symbols)

                    var candleCounts: [String: Int] = [:]
                    for symbol in probes {
                        candleCounts[symbol.description] = try await routedProvider.candles(
                            for: symbol,
                            period: .day,
                            count: 2
                        ).count
                    }

                    let quoteBySymbol = Dictionary(uniqueKeysWithValues: quotes.map { ($0.symbol, $0) })
                    let expectedLongbridge = probes.filter {
                        $0.indexID != .russell1000 && $0.indexID != .russell2000
                    }
                    let incorrectlyRouted = expectedLongbridge.filter {
                        quoteBySymbol[$0]?.sourceID != LongbridgeProvider.providerID
                    }
                    let unsupportedIndex = SymbolID(index: .russell1000)
                    let health = await routedProvider.healthReport()
                    let statusUpdates = await provider.connectionStatusUpdates()
                    var statusIterator = statusUpdates.makeAsyncIterator()
                    let connectionStatus = await statusIterator.next()

                    guard incorrectlyRouted.isEmpty,
                          quoteBySymbol[unsupportedIndex]?.sourceID == "yahoo",
                          candleCounts.values.allSatisfy({ $0 > 0 }),
                          health[LongbridgeProvider.providerID] == "healthy",
                          connectionStatus == .connected else {
                        throw ProviderError.badResponse(
                            "SDK watchlist check failed: quotes=\(quotes.count)/\(symbols.count), " +
                            "wrongRoutes=\(incorrectlyRouted), ruiSource=" +
                            "\(quoteBySymbol[unsupportedIndex]?.sourceID ?? "none"), " +
                            "candles=\(candleCounts), health=\(health), " +
                            "connection=\(String(describing: connectionStatus))"
                        )
                    }

                    let fallbackSymbols = quotes
                        .filter { $0.sourceID != LongbridgeProvider.providerID }
                        .map { $0.symbol.description }
                        .sorted()
                    print(
                        "PULSE_LONGBRIDGE_SDK_WATCHLIST_SELFTEST ok " +
                        "stored=\(storedSymbols.count) tested=\(symbols.count) " +
                        "quotes=\(quotes.count) longbridgeHealth=healthy connection=connected " +
                        "fallbackOnly=\(fallbackSymbols.joined(separator: ",")) " +
                        "candles=\(candleCounts)"
                    )
                    fflush(stdout)
                    exit(0)
                } catch {
                    print("PULSE_LONGBRIDGE_SDK_WATCHLIST_SELFTEST failed error=\(error)")
                    fflush(stdout)
                    exit(1)
                }
            }
            dispatchMain()
        }

        if CommandLine.arguments.contains("--longbridge-sdk-stability-selftest") {
            Task.detached {
                do {
                    let auth = try longbridgeSelfTestAuth()
                    let provider = LongbridgeProvider(auth: auth)
                    await provider.updateAuth(auth)

                    let symbol = SymbolID(market: .hk, code: "700")
                    try await provider.debugSDKSubscriptionRoundTrip(for: [symbol])
                    guard let stream = provider.quoteStream(for: [symbol]) else {
                        throw ProviderError.unsupported(.streaming)
                    }

                    let metrics = LongbridgeSDKStabilityMetrics()
                    let streamTask = Task {
                        var isSeed = true
                        do {
                            for try await quote in stream {
                                if isSeed {
                                    await metrics.recordSeed()
                                    isSeed = false
                                } else {
                                    await metrics.recordPush(quote)
                                }
                            }
                        } catch is CancellationError {
                            // Expected when the bounded stability window ends.
                        } catch {
                            await metrics.recordStreamError(error)
                        }
                    }

                    var latestPullPrice = 0.0
                    var candleCount = 0
                    let sampleCount = 12
                    for sample in 1...sampleCount {
                        guard let quote = try await provider.quotes(for: [symbol]).first else {
                            throw ProviderError.badResponse("SDK returned no quote for \(symbol)")
                        }
                        latestPullPrice = quote.price
                        if sample == 1 {
                            candleCount = try await provider.candles(
                                for: symbol,
                                period: .minute1,
                                count: 5
                            ).count
                        }
                        print(
                            "PULSE_LONGBRIDGE_SDK_STABILITY sample=\(sample)/\(sampleCount) " +
                            "price=\(String(format: "%.4f", quote.price))"
                        )
                        fflush(stdout)
                        if sample < sampleCount {
                            try await Task.sleep(for: .seconds(5))
                        }
                    }

                    streamTask.cancel()
                    await streamTask.value
                    let result = await metrics.snapshot()
                    if let streamError = result.streamError {
                        throw ProviderError.badResponse("SDK stream failed: \(streamError)")
                    }
                    guard result.seeds == 1, result.pushes > 0, candleCount > 0 else {
                        throw ProviderError.badResponse(
                            "SDK stability incomplete: seeds=\(result.seeds), " +
                            "pushes=\(result.pushes), candles=\(candleCount)"
                        )
                    }

                    print(
                        "PULSE_LONGBRIDGE_SDK_STABILITY ok transport=official-sdk-v4.4.1 " +
                        "duration=55s pulls=\(sampleCount) pushes=\(result.pushes) " +
                        "pullPrice=\(String(format: "%.4f", latestPullPrice)) " +
                        "pushPrice=\(String(format: "%.4f", result.latestPushPrice ?? 0)) " +
                        "candles=\(candleCount)"
                    )
                    fflush(stdout)
                    exit(0)
                } catch {
                    print("PULSE_LONGBRIDGE_SDK_STABILITY failed error=\(error)")
                    fflush(stdout)
                    exit(1)
                }
            }
            dispatchMain()
        }

        if CommandLine.arguments.contains("--longbridge-plugin-state-selftest") {
            let loaded = LongbridgePluginDebugProbe.isLoaded()
            print("PULSE_LONGBRIDGE_PLUGIN_STATE loaded=\(loaded)")
            fflush(stdout)
            exit(loaded ? 1 : 0)
        }

        if CommandLine.arguments.contains("--longbridge-plugin-selftest") {
            do {
                let result = try LongbridgePluginDebugProbe.loadAndValidate()
                print(
                    "PULSE_LONGBRIDGE_PLUGIN_SELFTEST ok " +
                    "sdk=\(result.sdkVersion) commit=\(result.sdkCommit) " +
                    "initiallyLoaded=\(result.wasLoadedBeforeProbe) " +
                    "nowLoaded=\(result.isLoadedAfterProbe) " +
                    "symbols=\(result.symbols.joined(separator: ",")) " +
                    "path=\(result.executablePath)"
                )
                fflush(stdout)
                exit(0)
            } catch {
                print("PULSE_LONGBRIDGE_PLUGIN_SELFTEST failed error=\(error.localizedDescription)")
                fflush(stdout)
                exit(1)
            }
        }
        if CommandLine.arguments.contains("--share-selftest") {
            Task { @MainActor in
                exit(runShareTest() ? 0 : 1)
            }
            return
        }
        if CommandLine.arguments.contains("--watchlist-sort-selftest") {
            exit(runWatchlistSortTest() ? 0 : 1)
        }

        guard CommandLine.arguments.contains("--selftest") else { return }
        Task.detached {
            let provider = CompositeProvider(providers: [BinanceProvider(), TencentProvider(), YahooProvider()])

            func report(_ label: String, _ operation: () async throws -> String) async {
                do {
                    print("SELFTEST \(label): ✅ \(try await operation())")
                } catch {
                    print("SELFTEST \(label): ❌ \(error)")
                }
            }

            await report("search(AAPL)") {
                let r = try await provider.search("AAPL")
                return "\(r.count) results — \(r.prefix(3).map { "\($0.name)(\($0.symbol))" }.joined(separator: ", "))"
            }
            await report("search(腾讯)") {
                let r = try await provider.search("腾讯")
                return "\(r.count) results — \(r.prefix(3).map { "\($0.name)(\($0.symbol))" }.joined(separator: ", "))"
            }
            await report("quotes(600519/700/AAPL)") {
                let r = try await provider.quotes(for: [
                    SymbolID(market: .sh, code: "600519"),
                    SymbolID(market: .hk, code: "700"),
                    SymbolID(market: .us, code: "AAPL"),
                ])
                return r.map { "\($0.symbol)=\($0.price)" }.joined(separator: ", ")
            }
            await report("candles(600519, minute1 Tencent)") {
                let r = try await provider.candles(
                    for: SymbolID(market: .sh, code: "600519"), period: .minute1, count: 60
                )
                return "\(r.count) points, latest \(r.last?.time.formatted(date: .omitted, time: .standard) ?? "—")"
            }
            await report("candles(AAPL, day)") {
                let r = try await provider.candles(for: SymbolID(market: .us, code: "AAPL"), period: .day, count: 30)
                return "\(r.count) candles, latest close \(r.last?.close ?? 0)"
            }
            await report("Binance crypto(BTC/USDT)") {
                let bitcoin = SymbolID(cryptoBase: "BTC", quote: "USDT")
                let quote = try await provider.quotes(for: [bitcoin]).first
                let candles = try await provider.candles(for: bitcoin, period: .minute1, count: 5)
                return "price \(quote?.price ?? 0), \(candles.count) candles"
            }

            // Reproduce a mixed-provider flow: Tencent supplies A-share quotes/minutes; Yahoo covers other candles.
            await report("user flow: add watchlist(000847.SH/700.HK/80700.HK) -> sparkline -> search again") {
                let flow = CompositeProvider(providers: [TencentProvider(), YahooProvider()])
                let added = [
                    SymbolID(market: .sh, code: "000847"),
                    SymbolID(market: .hk, code: "700"),
                    SymbolID(market: .hk, code: "80700"),
                ]
                let quotes = try await flow.quotes(for: added)
                var sparkOK = 0
                for symbol in added {
                    if let candles = try? await flow.candles(for: symbol, period: .minute5, count: 60),
                       !candles.isEmpty { sparkOK += 1 }
                }
                let again = try await flow.search("苹果")
                let health = await flow.healthReport()
                return "quotes \(quotes.count)/3, sparkline \(sparkOK)/3, re-search \(again.count) results, health=\(health)"
            }
            exit(0)
        }
    }

    private static func runWatchlistSortTest() -> Bool {
        let apple = WatchItem(
            symbol: SymbolID(market: .us, code: "AAPL"),
            displayName: "Apple"
        )
        let microsoft = WatchItem(
            symbol: SymbolID(market: .us, code: "MSFT"),
            displayName: "Microsoft"
        )
        let tesla = WatchItem(
            symbol: SymbolID(market: .us, code: "TSLA"),
            displayName: "Tesla"
        )
        let ondas = WatchItem(
            symbol: SymbolID(market: .us, code: "ONDS"),
            displayName: "Ondas"
        )
        let items = [apple, microsoft, tesla, ondas]

        func value(for item: WatchItem) -> Double? {
            switch item.symbol {
            case apple.symbol: 3
            case microsoft.symbol: 4
            case ondas.symbol: 4
            default: nil
            }
        }

        let pinnedOrder = WatchlistSortResolver.sortedSymbols(
            items: items,
            pinnedSymbols: [tesla.symbol, apple.symbol],
            value: value
        )
        let metricOrder = WatchlistSortResolver.sortedSymbols(
            items: items,
            pinnedSymbols: [],
            value: value
        )
        let customPinnedOrder = WatchlistSortResolver.pinnedFirstSymbols(
            items: items,
            pinnedSymbols: [tesla.symbol, apple.symbol]
        )
        let expectedPinnedOrder = [apple.symbol, tesla.symbol, microsoft.symbol, ondas.symbol]
        let expectedMetricOrder = [microsoft.symbol, ondas.symbol, apple.symbol, tesla.symbol]
        let expectedCustomPinnedOrder = [tesla.symbol, apple.symbol, microsoft.symbol, ondas.symbol]
        let passed = pinnedOrder == expectedPinnedOrder
            && metricOrder == expectedMetricOrder
            && customPinnedOrder == expectedCustomPinnedOrder

        if passed {
            print("WATCHLIST_SORT_SELFTEST: ✅ pinned-first custom and metric ordering, missing values, stable ties")
        } else {
            print(
                "WATCHLIST_SORT_SELFTEST: ❌ pinned=\(pinnedOrder) " +
                    "metric=\(metricOrder) custom=\(customPinnedOrder)"
            )
        }
        fflush(stdout)
        return passed
    }

    @MainActor
    private static func runShareTest() -> Bool {
        do {
            let metricTestItem = WatchItem(
                symbol: SymbolID(market: .us, code: "AAPL"),
                displayName: "Apple",
                lots: [CostLot(price: 200, quantity: 10)]
            )
            let metricTestQuote = Quote(
                symbol: metricTestItem.symbol,
                price: 231.42,
                previousClose: 228.50,
                currencyCode: "USD"
            )
            guard let metricTestPosition = PositionMetrics(item: metricTestItem, quote: metricTestQuote) else {
                throw ShareImageError.renderingFailed
            }
            let percentDisplay = WatchRowMetricDisplay.resolve(
                quote: metricTestQuote,
                metrics: metricTestPosition,
                mode: .changePercent,
                item: metricTestItem
            )
            let todayDisplay = WatchRowMetricDisplay.resolve(
                quote: metricTestQuote,
                metrics: metricTestPosition,
                mode: .todayPnL,
                item: metricTestItem
            )
            let totalDisplay = WatchRowMetricDisplay.resolve(
                quote: metricTestQuote,
                metrics: metricTestPosition,
                mode: .totalPnL,
                item: metricTestItem
            )
            guard percentDisplay.text.hasSuffix("%"),
                  todayDisplay.text.contains("$"),
                  totalDisplay.text.contains("$"),
                  todayDisplay.colorValue == metricTestPosition.todayPnL,
                  totalDisplay.colorValue == metricTestPosition.totalPnL else {
                throw ShareImageError.renderingFailed
            }

            func trendCandles(_ values: [Double], market: Market) -> [Candle] {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = market.timeZone
                let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)) ?? .now
                let startHour = market == .crypto ? 0 : 9
                let startMinute = market == .crypto ? 0 : 30
                let start = calendar.date(
                    bySettingHour: startHour,
                    minute: startMinute,
                    second: 0,
                    of: day
                ) ?? day
                return values.enumerated().map { index, close in
                    Candle(
                        time: start.addingTimeInterval(Double(index) * 60),
                        open: close,
                        high: close,
                        low: close,
                        close: close
                    )
                }
            }

            let snapshot = WatchlistShareSnapshot(
                rows: [
                    .init(
                        id: SymbolID(market: .us, code: "AAPL"),
                        name: "Apple",
                        market: .us,
                        symbolCode: "AAPL",
                        priceText: "231.42",
                        metricText: "+$29.20",
                        metricColorValue: 2.92,
                        change: 2.92,
                        previousClose: 228.50,
                        sessionLabel: nil,
                        sparkline: trendCandles([228.5, 229.2, 228.9, 230.4, 231.0, 231.42], market: .us)
                    ),
                    .init(
                        id: SymbolID(market: .hk, code: "700"),
                        name: "腾讯控股",
                        market: .hk,
                        symbolCode: "700",
                        priceText: "542.50",
                        metricText: "+HK$45.00",
                        metricColorValue: 4.50,
                        change: 4.50,
                        previousClose: 538.00,
                        sessionLabel: nil,
                        sparkline: trendCandles([538, 539, 537.8, 540.2, 541.6, 542.5], market: .hk)
                    ),
                    .init(
                        id: SymbolID(market: .sh, code: "600519"),
                        name: "贵州茅台",
                        market: .sh,
                        symbolCode: "600519",
                        priceText: "1,482.30",
                        metricText: "-¥54.00",
                        metricColorValue: -5.40,
                        change: -5.40,
                        previousClose: 1487.70,
                        sessionLabel: nil,
                        sparkline: trendCandles([1487.7, 1485.2, 1486.4, 1483.8, 1484.5, 1482.3], market: .sh)
                    ),
                    .init(
                        id: SymbolID(market: .us, code: "MSFT"),
                        name: "Microsoft",
                        market: .us,
                        symbolCode: "MSFT",
                        priceText: "497.72",
                        metricText: "+$23.40",
                        metricColorValue: 2.34,
                        change: 2.34,
                        previousClose: 495.38,
                        sessionLabel: nil,
                        sparkline: trendCandles([495.4, 496.1, 495.8, 496.9, 497.1, 497.72], market: .us)
                    ),
                    .init(
                        id: SymbolID(market: .us, code: "NVDA"),
                        name: "NVIDIA",
                        market: .us,
                        symbolCode: "NVDA",
                        priceText: "164.92",
                        metricText: "-$10.30",
                        metricColorValue: -1.03,
                        change: -1.03,
                        previousClose: 165.95,
                        sessionLabel: nil,
                        sparkline: trendCandles([165.9, 165.5, 165.8, 165.1, 164.7, 164.92], market: .us)
                    ),
                    .init(
                        id: SymbolID(market: .hk, code: "9988"),
                        name: "阿里巴巴-W",
                        market: .hk,
                        symbolCode: "9988",
                        priceText: "111.80",
                        metricText: "+HK$16.00",
                        metricColorValue: 1.60,
                        change: 1.60,
                        previousClose: 110.20,
                        sessionLabel: nil,
                        sparkline: trendCandles([110.2, 110.6, 110.4, 111.0, 111.5, 111.8], market: .hk)
                    ),
                    .init(
                        id: SymbolID(cryptoBase: "BTC", quote: "USDT"),
                        name: "Bitcoin USD",
                        market: .crypto,
                        symbolCode: "BTC/USDT",
                        priceText: "116,420.00",
                        metricText: "+$2,460.00",
                        metricColorValue: 2460,
                        change: 2460,
                        previousClose: 113960,
                        sessionLabel: nil,
                        sparkline: trendCandles([113960, 114800, 114300, 115400, 116000, 116420], market: .crypto)
                    ),
                ],
                redUp: true,
                title: "My Watchlist",
                dateText: "Jul 29, Wed",
                updatedAtText: PulseLocalization.localizedString("refresh.updatedAt", "09:45")
            )
            let palette = ChangePalette(redUp: snapshot.redUp)
            let card = PulseShareCard(
                ambientColor: snapshot.ambientChange.map(palette.color(for:))
            ) {
                WatchlistShareContent(snapshot: snapshot)
            }
            let artifact = try ShareImageRenderer.render(
                card,
                configuration: .watchlistSquare(
                    height: snapshot.preferredImageHeight,
                    colorScheme: .light,
                    locale: Locale(identifier: "en")
                )
            )

            // 7 rows fit inside the 1:1 base canvas (1280×1280 at 2x).
            let pasteboard = NSPasteboard.withUniqueName()
            try ClipboardImageExporter.write(artifact, to: pasteboard)
            guard pasteboard.data(forType: .png) != nil,
                  pasteboard.data(forType: .tiff) != nil,
                  let bitmap = NSBitmapImageRep(data: artifact.pngData),
                  bitmap.pixelsWide == 1280,
                  bitmap.pixelsHigh == 1280 else {
                throw ShareImageError.clipboardWriteFailed
            }

            let shortSnapshot = WatchlistShareSnapshot(
                rows: Array(snapshot.rows.prefix(1)),
                redUp: snapshot.redUp,
                title: snapshot.title,
                dateText: snapshot.dateText,
                updatedAtText: snapshot.updatedAtText
            )
            guard snapshot.titleColumnWidth > shortSnapshot.titleColumnWidth,
                  snapshot.priceColumnWidth > shortSnapshot.priceColumnWidth,
                  snapshot.pillColumnWidth > shortSnapshot.pillColumnWidth else {
                throw ShareImageError.renderingFailed
            }

            // Long lists keep the 640pt width and grow taller instead of dropping rows.
            let tallRows = snapshot.rows + snapshot.rows.map { row in
                WatchlistShareSnapshot.Row(
                    id: SymbolID(market: row.market == .crypto ? .us : row.market, code: row.symbolCode + "X"),
                    name: row.name,
                    market: row.market,
                    symbolCode: row.symbolCode,
                    priceText: row.priceText,
                    metricText: row.metricText,
                    metricColorValue: row.metricColorValue,
                    change: row.change,
                    previousClose: row.previousClose,
                    sessionLabel: row.sessionLabel,
                    sparkline: row.sparkline
                )
            }
            let tallSnapshot = WatchlistShareSnapshot(
                rows: tallRows,
                redUp: snapshot.redUp,
                title: snapshot.title,
                dateText: snapshot.dateText,
                updatedAtText: snapshot.updatedAtText
            )
            guard shortSnapshot.preferredImageHeight == WatchlistShareSnapshot.baseImageSize,
                  tallSnapshot.preferredImageHeight > WatchlistShareSnapshot.baseImageSize else {
                throw ShareImageError.renderingFailed
            }
            let tallCard = PulseShareCard(
                ambientColor: tallSnapshot.ambientChange.map(palette.color(for:))
            ) {
                WatchlistShareContent(snapshot: tallSnapshot)
            }
            let tallArtifact = try ShareImageRenderer.render(
                tallCard,
                configuration: .watchlistSquare(
                    height: tallSnapshot.preferredImageHeight,
                    colorScheme: .light,
                    locale: Locale(identifier: "en")
                )
            )
            guard let tallBitmap = NSBitmapImageRep(data: tallArtifact.pngData),
                  tallBitmap.pixelsWide == 1280,
                  tallBitmap.pixelsHigh == Int(tallSnapshot.preferredImageHeight * 2) else {
                throw ShareImageError.renderingFailed
            }

            let detailQuote = Quote(
                symbol: metricTestItem.symbol,
                name: "Apple",
                price: 231.42,
                previousClose: 228.50,
                open: 229.10,
                high: 232.18,
                low: 227.82,
                volume: 48_260_000,
                currencyCode: "USD",
                marketState: .regular
            )
            let detailValues = (0..<120).map { index in
                let minute = Double(index)
                return 228.5 + minute * 0.024 + sin(minute / 8) * 0.72 + sin(minute / 2.7) * 0.18
            }
            let detailCandles = trendCandles(detailValues, market: .us)
            let detailSnapshot = DetailShareSnapshot(
                symbol: metricTestItem.symbol,
                name: "Apple",
                quote: detailQuote,
                period: .minute1,
                candles: detailCandles,
                redUp: true,
                updatedAtText: PulseLocalization.localizedString("refresh.updatedAt", "09:45")
            )
            let detailCard = PulseShareCard(
                ambientColor: detailSnapshot.changeValue.map(palette.color(for:))
            ) {
                DetailShareContent(snapshot: detailSnapshot)
            }
            let detailArtifact = try ShareImageRenderer.render(
                detailCard,
                configuration: .detailLandscape(
                    colorScheme: .light,
                    locale: Locale(identifier: "en")
                )
            )
            let darkDetailArtifact = try ShareImageRenderer.render(
                detailCard,
                configuration: .detailLandscape(
                    colorScheme: .dark,
                    locale: Locale(identifier: "en")
                )
            )
            // 16:9 landscape (1920×1080 at 2x) in both appearances.
            guard let detailBitmap = NSBitmapImageRep(data: detailArtifact.pngData),
                  let darkDetailBitmap = NSBitmapImageRep(data: darkDetailArtifact.pngData),
                  detailBitmap.pixelsWide == 1920,
                  detailBitmap.pixelsHigh == 1080,
                  darkDetailBitmap.pixelsWide == 1920,
                  darkDetailBitmap.pixelsHigh == 1080 else {
                throw ShareImageError.renderingFailed
            }

            // Fixed-English text exports keep raw data machine-readable, preserve item order
            // and source metadata, and never receive position or trade fields.
            let exportedAt = ISO8601DateFormatter().date(from: "2026-07-15T16:00:00Z")!
            let privateItem = WatchItem(
                symbol: metricTestItem.symbol,
                displayName: "Apple",
                instrumentType: .equity,
                lots: [CostLot(price: 987_654.321, quantity: 12_345.678)]
            )
            var textQuote = detailQuote
            textQuote.timestamp = detailCandles.last?.time ?? exportedAt
            textQuote.sourceID = "longbridge"
            textQuote.sourceName = "Longbridge"
            textQuote.sourceDelay = 0

            // Exercise the same WatchlistStore + MarketStore constructor used by AppState,
            // with isolated persistence so this test never touches the user's watchlist.
            let defaultsSuite = "app.pulse.share-selftest.\(UUID().uuidString)"
            guard let isolatedDefaults = UserDefaults(suiteName: defaultsSuite) else {
                throw MarketTextSnapshotError.encodingFailed
            }
            isolatedDefaults.removePersistentDomain(forName: defaultsSuite)
            defer { isolatedDefaults.removePersistentDomain(forName: defaultsSuite) }
            let productionWatchlist = WatchlistStore(
                defaults: isolatedDefaults,
                defaultGroupName: "AI Export"
            )
            productionWatchlist.add(SymbolInfo(
                symbol: privateItem.symbol,
                name: privateItem.resolvedDisplayName,
                type: .equity
            ))
            productionWatchlist.updateLots(
                privateItem.symbol,
                lots: [CostLot(price: 987_654.321, quantity: 12_345.678)]
            )
            productionWatchlist.addTransaction(
                privateItem.symbol,
                PositionTransaction(kind: .buy, price: 876_543.219, quantity: 54_321.987)
            )
            let productionMarket = MarketStore()
            productionMarket.apply(quotes: [textQuote])
            productionMarket.apply(sparkline: detailCandles, for: privateItem.symbol)
            let productionText = try WatchlistTextSnapshot(
                watchlist: productionWatchlist,
                market: productionMarket,
                exportedAt: exportedAt
            ).renderedText()
            guard !productionText.contains("987654.321"),
                  !productionText.contains("12345.678"),
                  !productionText.contains("876543.219"),
                  !productionText.contains("54321.987"),
                  let productionItems = try decodedTextSnapshot(productionText)["items"] as? [[String: Any]],
                  productionItems.count == 1 else {
                throw MarketTextSnapshotError.encodingFailed
            }

            let watchlistText = try WatchlistTextSnapshot(
                groupName: "AI Export",
                items: [
                    .init(
                        symbol: privateItem.symbol,
                        name: privateItem.resolvedDisplayName,
                        instrumentType: privateItem.resolvedInstrumentType,
                        quote: textQuote,
                        intradayCandles: detailCandles
                    ),
                    .init(
                        symbol: SymbolID(market: .sh, code: "600519"),
                        name: "贵州茅台",
                        instrumentType: .equity,
                        quote: nil,
                        intradayCandles: []
                    ),
                ],
                exportedAt: exportedAt
            ).renderedText()
            let watchlistPayload = try decodedTextSnapshot(watchlistText)
            guard watchlistText.hasPrefix("This market snapshot was exported by Pulse."),
                  !watchlistText.contains("987654.321"),
                  !watchlistText.contains("12345.678"),
                  !watchlistText.contains("—"),
                  watchlistPayload["exported_at"] as? String == "2026-07-15T16:00:00Z",
                  watchlistPayload["format"] as? String == "pulse_market_snapshot",
                  let view = watchlistPayload["view"] as? [String: Any],
                  view["type"] as? String == "watchlist",
                  view["group_name"] as? String == "AI Export",
                  let textItems = watchlistPayload["items"] as? [[String: Any]],
                  textItems.count == 2,
                  textItems[0]["order"] as? Int == 1,
                  textItems[1]["order"] as? Int == 2,
                  let firstQuote = textItems[0]["quote"] as? [String: Any],
                  firstQuote["session"] as? String == "regular",
                  firstQuote["timestamp"] as? String == "2026-07-15T11:29:00-04:00",
                  let firstSource = firstQuote["source"] as? [String: Any],
                  firstSource["id"] as? String == "longbridge",
                  let secondInstrument = textItems[1]["instrument"] as? [String: Any],
                  secondInstrument["name"] as? String == "贵州茅台",
                  textItems[1]["quote"] is NSNull,
                  textItems[1]["intraday_summary"] is NSNull else {
                throw MarketTextSnapshotError.encodingFailed
            }

            // Exported session scopes are exact even though chart framing tolerates
            // provider bars one minute outside the opening and closing boundaries.
            var usCalendar = Calendar(identifier: .gregorian)
            usCalendar.timeZone = Market.us.timeZone
            let usDay = usCalendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
            func usCandle(hour: Int, minute: Int, price: Double) -> Candle {
                let time = usCalendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: usDay
                )!
                return Candle(
                    time: time,
                    open: price,
                    high: price + 0.01,
                    low: price - 0.01,
                    close: price,
                    volume: 1
                )
            }
            let boundaryCandles = [
                usCandle(hour: 9, minute: 29, price: 7.71),
                usCandle(hour: 9, minute: 30, price: 7.72),
                usCandle(hour: 16, minute: 0, price: 7.49),
                usCandle(hour: 16, minute: 1, price: 7.48),
            ]
            let boundaryText = try WatchlistTextSnapshot(
                groupName: "Boundaries",
                items: [
                    .init(
                        symbol: privateItem.symbol,
                        name: privateItem.resolvedDisplayName,
                        instrumentType: privateItem.resolvedInstrumentType,
                        quote: textQuote,
                        intradayCandles: boundaryCandles
                    ),
                ],
                exportedAt: exportedAt
            ).renderedText()
            let boundaryPayload = try decodedTextSnapshot(boundaryText)
            guard let boundaryItems = boundaryPayload["items"] as? [[String: Any]],
                  let boundarySummary = boundaryItems.first?["intraday_summary"] as? [String: Any],
                  boundarySummary["bar_count"] as? Int == 2,
                  boundarySummary["start_at"] as? String == "2026-07-15T09:30:00-04:00",
                  boundarySummary["end_at"] as? String == "2026-07-15T16:00:00-04:00",
                  boundarySummary["open"] as? Double == 7.72,
                  boundarySummary["close"] as? Double == 7.49 else {
                throw MarketTextSnapshotError.encodingFailed
            }

            let boundaryDetailText = try DetailTextSnapshot(
                symbol: privateItem.symbol,
                name: privateItem.resolvedDisplayName,
                instrumentType: privateItem.resolvedInstrumentType,
                quote: textQuote,
                period: .minute1,
                candles: boundaryCandles,
                includesExtendedHours: false,
                exportedAt: exportedAt
            ).renderedText()
            let boundaryDetailPayload = try decodedTextSnapshot(boundaryDetailText)
            guard let boundaryChart = boundaryDetailPayload["chart"] as? [String: Any],
                  let boundaryAggregation = boundaryChart["aggregation"] as? [String: Any],
                  boundaryAggregation["input_bar_count"] as? Int == 2,
                  boundaryChart["visible_from"] as? String == "2026-07-15T09:30:00-04:00",
                  boundaryChart["visible_to"] as? String == "2026-07-15T16:00:00-04:00" else {
                throw MarketTextSnapshotError.encodingFailed
            }

            // Crypto is a continuous session regardless of a provider's stock-shaped
            // MarketState value, and high-precision quantities remain clean JSON numbers.
            let bitcoin = SymbolID(cryptoBase: "BTC", quote: "USDT")
            let cryptoQuote = Quote(
                symbol: bitcoin,
                name: "BTC",
                price: 63_136,
                previousClose: 63_396.63,
                high: 63_796.33,
                low: 62_982.38,
                volume: 7_696.4130699999996,
                turnover: 487_579_750.31443441,
                currencyCode: "USDT",
                sourceID: "binance",
                sourceName: "Binance",
                sourceDelay: 0,
                timestamp: exportedAt,
                marketState: .regular
            )
            let cryptoText = try WatchlistTextSnapshot(
                groupName: "Crypto",
                items: [
                    .init(
                        symbol: bitcoin,
                        name: "BTC",
                        instrumentType: .crypto,
                        quote: cryptoQuote,
                        intradayCandles: []
                    ),
                ],
                exportedAt: exportedAt
            ).renderedText()
            let cryptoPayload = try decodedTextSnapshot(cryptoText)
            guard let cryptoItems = cryptoPayload["items"] as? [[String: Any]],
                  let exportedCryptoQuote = cryptoItems.first?["quote"] as? [String: Any],
                  exportedCryptoQuote["session"] as? String == "continuous",
                  cryptoText.contains("\"volume\" : 7696.41307"),
                  cryptoText.contains("\"turnover\" : 487579750.31") else {
                throw MarketTextSnapshotError.encodingFailed
            }

            let textPasteboard = NSPasteboard.withUniqueName()
            textPasteboard.clearContents()
            textPasteboard.setData(Data([0x01]), forType: .png)
            try ClipboardTextExporter.write(watchlistText, to: textPasteboard)
            guard textPasteboard.string(forType: .string) == watchlistText,
                  textPasteboard.data(forType: .png) == nil else {
                throw ClipboardTextError.writeFailed
            }

            let chartStart = detailCandles.first?.time ?? exportedAt
            let longChart = (0..<241).map { index in
                let base = 200 + Double(index) * 0.1
                return Candle(
                    time: chartStart.addingTimeInterval(Double(index) * 5 * 60),
                    open: base,
                    high: base + 0.8,
                    low: base - 0.6,
                    close: base + 0.2,
                    volume: Double(index + 1) * 100
                )
            }
            var missingReferenceQuote = textQuote
            missingReferenceQuote.previousClose = 0
            missingReferenceQuote.marketState = .postMarket
            missingReferenceQuote.regularSession = .init(price: 229.5, previousClose: nil)
            let detailText = try DetailTextSnapshot(
                symbol: privateItem.symbol,
                name: privateItem.resolvedDisplayName,
                instrumentType: privateItem.resolvedInstrumentType,
                quote: missingReferenceQuote,
                period: .minute5,
                candles: longChart,
                includesExtendedHours: true,
                exportedAt: exportedAt
            ).renderedText()
            let detailPayload = try decodedTextSnapshot(detailText)
            guard let chart = detailPayload["chart"] as? [String: Any],
                  chart["period"] as? String == "5m",
                  chart["includes_extended_hours"] as? Bool == true,
                  chart["session_scope"] as? String == "pre_market_regular_post_market",
                  chart["source"] is NSNull,
                  let aggregation = chart["aggregation"] as? [String: Any],
                  aggregation["method"] as? String == "contiguous_ohlcv",
                  aggregation["input_bar_count"] as? Int == 241,
                  aggregation["output_bar_count"] as? Int == 81,
                  aggregation["source_bars_per_output_bar"] as? Int == 3,
                  let bars = chart["bars"] as? [[Any]],
                  bars.count == 81,
                  bars.allSatisfy({ $0.count == 6 }),
                  let exportedQuote = detailPayload["quote"] as? [String: Any],
                  exportedQuote["previous_close"] is NSNull,
                  exportedQuote["change"] is NSNull,
                  exportedQuote["change_percent"] is NSNull,
                  let regularClose = exportedQuote["regular_session_close"] as? [String: Any],
                  regularClose["previous_close"] is NSNull,
                  regularClose["change"] is NSNull,
                  regularClose["change_percent"] is NSNull,
                  detailText.split(separator: "\n").filter({ $0.hasPrefix("      [\"") }).count == 81,
                  !detailText.contains("\"bars\" : [\n      [\n"),
                  !detailText.contains("200.199999999") else {
                throw MarketTextSnapshotError.encodingFailed
            }

            let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pulse-share-selftest.png")
            try artifact.pngData.write(to: outputURL, options: .atomic)
            let tallOutputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pulse-share-selftest-tall.png")
            try tallArtifact.pngData.write(to: tallOutputURL, options: .atomic)
            let detailOutputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pulse-detail-share-selftest.png")
            try detailArtifact.pngData.write(to: detailOutputURL, options: .atomic)
            let darkDetailOutputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pulse-detail-share-selftest-dark.png")
            try darkDetailArtifact.pngData.write(to: darkDetailOutputURL, options: .atomic)
            print(
                "SHARE_SELFTEST: ✅ image and English text exports copied to isolated pasteboards, "
                    + "images=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh),tall="
                    + "\(tallBitmap.pixelsWide)x\(tallBitmap.pixelsHigh), detail="
                    + "\(detailBitmap.pixelsWide)x\(detailBitmap.pixelsHigh), darkDetail="
                    + "\(darkDetailBitmap.pixelsWide)x\(darkDetailBitmap.pixelsHigh), outputs="
                    + "\(tallOutputURL.path),\(outputURL.path),\(detailOutputURL.path),"
                    + darkDetailOutputURL.path
            )

            // Sandboxed builds keep the PNGs inside the app container; the base64 dump
            // lets external tooling (CI, agents) inspect renders without container access.
            if ProcessInfo.processInfo.environment["PULSE_SHARE_SELFTEST_BASE64"] == "1" {
                let dumps = [
                    ("watchlist", artifact.pngData),
                    ("watchlist-tall", tallArtifact.pngData),
                    ("detail-light", detailArtifact.pngData),
                    ("detail-dark", darkDetailArtifact.pngData),
                ]
                for (name, data) in dumps {
                    print("SHARE_SELFTEST_B64:\(name):\(data.base64EncodedString())")
                }
            }
            return true
        } catch {
            print("SHARE_SELFTEST: ❌ \(error)")
            return false
        }
    }

    private static func decodedTextSnapshot(_ text: String) throws -> [String: Any] {
        let opening = "```json\n"
        guard let start = text.range(of: opening),
              let end = text.range(of: "\n```", options: .backwards),
              start.upperBound <= end.lowerBound else {
            throw MarketTextSnapshotError.encodingFailed
        }
        let data = Data(text[start.upperBound..<end.lowerBound].utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MarketTextSnapshotError.encodingFailed
        }
        return object
    }
}
