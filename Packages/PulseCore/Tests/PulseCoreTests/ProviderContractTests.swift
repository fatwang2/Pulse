import Foundation
import Testing
@testable import PulseCore

/// Provider contract tests: every data source (built-in or future plugin) must pass the same set of assertions.
/// They hit the real network and are skipped by default; enable with `PULSE_LIVE_TESTS=1 swift test`.
@Suite("Provider contract (live)", .enabled(if: ProcessInfo.processInfo.environment["PULSE_LIVE_TESTS"] == "1"))
struct ProviderContractTests {
    static let testSymbols = [
        SymbolID(market: .us, code: "AAPL"),
        SymbolID(market: .hk, code: "700"),
        SymbolID(market: .sh, code: "600519"),
    ]

    static func assertQuoteContract(_ quote: Quote) {
        #expect(quote.price > 0, "Price must be positive")
        #expect(quote.previousClose > 0, "Previous close must be positive")
        #expect(abs(quote.changePercent) < 50, "Single-day change should not exceed ±50% (data sanity check)")
        if let high = quote.high, let low = quote.low {
            #expect(high >= low, "High must be >= low")
        }
        #expect(quote.timestamp <= Date.now.addingTimeInterval(3600), "Timestamp should not be in the future")
    }

    static func assertCandleContract(_ candles: [Candle]) {
        #expect(!candles.isEmpty, "Candles should not be empty")
        for candle in candles {
            #expect(candle.high >= candle.low)
            #expect(candle.high >= max(candle.open, candle.close) - 0.0001)
            #expect(candle.low <= min(candle.open, candle.close) + 0.0001)
        }
        // Ascending time order
        let times = candles.map(\.time)
        #expect(times == times.sorted(), "Candles must be in ascending time order")
    }

    @Test("Tencent: batch quotes")
    func tencentQuotes() async throws {
        let quotes = try await TencentProvider().quotes(for: Self.testSymbols)
        #expect(quotes.count == Self.testSymbols.count)
        for quote in quotes { Self.assertQuoteContract(quote) }
    }

    @Test("Tencent: A-share intraday")
    func tencentIntraday() async throws {
        let candles = try await TencentProvider().candles(
            for: SymbolID(market: .sh, code: "600519"), period: .minute1, count: 60
        )
        Self.assertCandleContract(candles)
        #expect(candles.count <= 60)
    }

    @Test("Tencent: metal quotes")
    func tencentMetalQuotes() async throws {
        // The international channel only: Tencent does not serve `nf_` domestic futures.
        let metals = PreciousMetalID.allCases
            .filter { $0.market == .metal }
            .map { SymbolID(metal: $0) }
        let quotes = try await TencentProvider().quotes(for: metals)
        #expect(quotes.count == metals.count)
        for quote in quotes {
            Self.assertQuoteContract(quote)
            #expect(quote.currencyCode == "USD")
        }
    }

    @Test("Yahoo: quotes")
    func yahooQuotes() async throws {
        let quotes = try await YahooProvider().quotes(for: [SymbolID(market: .hk, code: "700")])
        #expect(quotes.count == 1)
        for quote in quotes { Self.assertQuoteContract(quote) }
    }

    @Test("Yahoo: candles", arguments: [CandlePeriod.day, .week])
    func yahooCandles(period: CandlePeriod) async throws {
        let candles = try await YahooProvider().candles(
            for: SymbolID(market: .us, code: "AAPL"), period: period, count: 60)
        Self.assertCandleContract(candles)
        #expect(candles.count <= 60)
    }

    @Test("Yahoo: metal candles", arguments: [CandlePeriod.day, .minute5])
    func yahooMetalCandles(period: CandlePeriod) async throws {
        let candles = try await YahooProvider().candles(
            for: SymbolID(metal: .gold), period: period, count: 30)
        Self.assertCandleContract(candles)
        #expect(candles.count <= 30)
    }

    @Test("Yahoo: search")
    func yahooSearch() async throws {
        let results = try await YahooProvider().search("tencent")
        #expect(results.contains { $0.symbol == SymbolID(market: .hk, code: "700") })
    }

    @Test("Yahoo: Tokyo and Seoul quotes carry their own currency", arguments: [
        (SymbolID(market: .jp, code: "7203"), "JPY"),
        (SymbolID(market: .kr, code: "005930"), "KRW"),
        (SymbolID(market: .kq, code: "247540"), "KRW"),
    ])
    func yahooJapanKoreaQuotes(symbol: SymbolID, currency: String) async throws {
        let quotes = try await YahooProvider().quotes(for: [symbol])
        let quote = try #require(quotes.first)
        Self.assertQuoteContract(quote)
        #expect(quote.currencyCode == currency)
    }

    @Test("Yahoo: Tokyo and Seoul intraday", arguments: [
        SymbolID(market: .jp, code: "7203"),
        SymbolID(market: .kr, code: "005930"),
    ])
    func yahooJapanKoreaIntraday(symbol: SymbolID) async throws {
        let candles = try await YahooProvider().candles(for: symbol, period: .minute1, count: 400)
        Self.assertCandleContract(candles)

        // Every bar must land inside the exchange's own session, which is the one
        // thing a wrong time zone or a wrong close time would break.
        let session = IntradayTradingSession(
            market: symbol.market,
            referenceDate: try #require(candles.last).time
        )
        let strays = candles.filter { !session.contains($0.time) }
        #expect(strays.isEmpty, "bars outside the session: \(strays.prefix(3).map(\.time))")
    }

    /// Yahoo indexes English names and tickers only: `任天堂` and `삼성전자`
    /// return nothing, which is why native-language search is not wired here yet.
    ///
    /// Yahoo's search endpoint throttles well before its quote endpoint does, and
    /// the provider turns Yahoo's rejection into an empty list rather than an
    /// error. Both outcomes mean "no signal", not "the mapping is wrong".
    private func searchOrSkip(_ query: String) async throws -> [SymbolInfo]? {
        let results: [SymbolInfo]
        do {
            results = try await YahooProvider().search(query)
        } catch ProviderError.rateLimited {
            return nil
        }
        return results.isEmpty ? nil : results
    }

    /// The exchange code is the only query Yahoo answers dependably for these two
    /// markets. An English name competes with every ADR, CEDEAR and German
    /// listing of the same company and frequently loses: "nintendo" returns no
    /// Tokyo listing at all, and "sony" was observed returning 6758.T, then only
    /// 8729.T, then nothing Japanese, across three runs an hour apart. Nothing
    /// here asserts that ranking — it is Yahoo's, not Pulse's. Native-language
    /// queries return nothing whatsoever: Yahoo indexes no Japanese or Korean
    /// names, which is why Naver carries Korean search and Japan has none yet.
    @Test("Yahoo: an exchange code finds the Tokyo or Seoul listing", arguments: [
        ("7203", SymbolID(market: .jp, code: "7203")),
        ("6758", SymbolID(market: .jp, code: "6758")),
        ("005930", SymbolID(market: .kr, code: "005930")),
    ])
    func yahooJapanKoreaCodeSearch(query: String, expected: SymbolID) async throws {
        guard let results = try await searchOrSkip(query) else { return }
        #expect(results.contains { $0.symbol == expected })
    }

    @Test("Yahoo: the Japanese and Korean headline indices resolve", arguments: [
        MarketIndexID.nikkei225, .kospi,
    ])
    func yahooJapanKoreaIndices(index: MarketIndexID) async throws {
        let quotes = try await YahooProvider().quotes(for: [SymbolID(index: index)])
        let quote = try #require(quotes.first)
        Self.assertQuoteContract(quote)
    }

    @Test("Naver: Korean quotes arrive in real time", arguments: [
        SymbolID(market: .kr, code: "005930"),
        SymbolID(market: .kq, code: "247540"),
        SymbolID(index: .kospi),
    ])
    func naverQuotes(symbol: SymbolID) async throws {
        let quote = try #require(try await NaverProvider().quotes(for: [symbol]).first)
        Self.assertQuoteContract(quote)
        #expect(quote.symbol == symbol)
        #expect(quote.currencyCode == "KRW")
    }

    @Test("Naver: one request answers for a whole batch across both boards")
    func naverBatchQuotes() async throws {
        let symbols = [
            SymbolID(market: .kr, code: "005930"),
            SymbolID(market: .kr, code: "105560"),
            SymbolID(market: .kq, code: "247540"),
        ]
        let quotes = try await NaverProvider().quotes(for: symbols)
        #expect(quotes.count == symbols.count)
        #expect(Set(quotes.map(\.symbol)) == Set(symbols))
        for quote in quotes { Self.assertQuoteContract(quote) }
    }

    /// The reason this provider exists: Yahoo cannot find a Korean company by
    /// its Korean name, and it cannot say which board a code belongs to.
    @Test("Naver: Korean names are searchable and carry their board")
    func naverSearch() async throws {
        let naver = NaverProvider()

        let samsung = try await naver.search("삼성전자")
        #expect(samsung.contains { $0.symbol == SymbolID(market: .kr, code: "005930") })

        // 에코프로비엠 is KOSDAQ; a result that called it KOSPI would send every
        // later request to Yahoo's `.KS` symbol, which is a different instrument.
        let ecopro = try await naver.search("에코프로비엠")
        #expect(ecopro.contains { $0.symbol == SymbolID(market: .kq, code: "247540") })

        // Yahoo returns nothing at all for the same query.
        let yahooKorean = (try? await YahooProvider().search("삼성전자")) ?? []
        #expect(!yahooKorean.contains { $0.symbol.market.isKorea })
    }

    @Test("Naver: candles at every offered resolution", arguments: [
        CandlePeriod.minute1, .minute5, .day, .week, .month,
    ])
    func naverCandles(period: CandlePeriod) async throws {
        let candles = try await NaverProvider().candles(
            for: SymbolID(market: .kr, code: "005930"), period: period, count: 40)
        Self.assertCandleContract(candles)
        #expect(candles.count > 1)
        #expect(candles.count <= 40)
    }

    /// Naver and Yahoo must be describing the same instrument. Their live prices
    /// differ by design — one is real time, the other twenty minutes behind — so
    /// the check is on the previous close, a number both have settled on.
    @Test("Naver and Yahoo agree on what a Korean code means", arguments: [
        SymbolID(market: .kr, code: "005930"),
        SymbolID(market: .kq, code: "247540"),
    ])
    func naverAgreesWithYahoo(symbol: SymbolID) async throws {
        let naver = try #require(try await NaverProvider().quotes(for: [symbol]).first)
        let yahoo = try #require(try await YahooProvider().quotes(for: [symbol]).first)
        let drift = abs(naver.previousClose - yahoo.previousClose) / yahoo.previousClose
        #expect(drift < 0.005, "previous close \(naver.previousClose) vs \(yahoo.previousClose)")
    }

    /// Korea has a real-time source now, so nothing should reach the delayed one
    /// while it is healthy — quotes, charts and the index alike.
    @Test("Composite: Korea routes to Naver, not to Yahoo", arguments: [
        SymbolID(market: .kr, code: "005930"),
        SymbolID(market: .kq, code: "247540"),
        SymbolID(index: .kospi),
    ])
    func compositeKorea(symbol: SymbolID) async throws {
        let composite = CompositeProvider(providers: [
            BinanceProvider(), TencentProvider(), NaverProvider(), YahooProvider(),
        ])
        let quote = try #require(try await composite.quotes(for: [symbol]).first)
        Self.assertQuoteContract(quote)
        #expect(quote.sourceID == NaverProvider.providerID)
        #expect(quote.sourceDelay == 0)

        let candles = try await composite.candles(for: symbol, period: .minute1, count: 60)
        Self.assertCandleContract(candles)
    }

    @Test("Binance: crypto quotes and candles")
    func binanceCrypto() async throws {
        let provider = BinanceProvider()
        let bitcoin = SymbolID(cryptoBase: "BTC", quote: "USDT")
        let quote = try #require(try await provider.quotes(for: [bitcoin]).first)
        Self.assertQuoteContract(quote)

        let candles = try await provider.candles(for: bitcoin, period: .minute1, count: 5)
        Self.assertCandleContract(candles)
        #expect(candles.count <= 5)
    }

    @Test("Binance: symbol catalog search")
    func binanceSearch() async throws {
        let results = try await BinanceProvider().search("BTC/USDT")
        #expect(results.first?.symbol == SymbolID(cryptoBase: "BTC", quote: "USDT"))
    }

    @Test("Binance: crypto WebSocket stream")
    func binanceCryptoStream() async throws {
        struct StreamEnded: Error {}
        struct TimedOut: Error {}

        let bitcoin = SymbolID(cryptoBase: "BTC", quote: "USDT")
        let stream = try #require(BinanceProvider().quoteStream(for: [bitcoin]))
        let quote = try await withThrowingTaskGroup(of: Quote.self) { group in
            group.addTask {
                for try await quote in stream { return quote }
                throw StreamEnded()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(12))
                throw TimedOut()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        Self.assertQuoteContract(quote)
        #expect(quote.symbol == bitcoin)
    }

    @Test("Composite: routing and merging")
    func composite() async throws {
        let composite = CompositeProvider(providers: [BinanceProvider(), TencentProvider(), YahooProvider()])
        let quotes = try await composite.quotes(for: Self.testSymbols)
        #expect(quotes.count == Self.testSymbols.count)
        let candles = try await composite.candles(for: Self.testSymbols[0], period: .day, count: 30)
        Self.assertCandleContract(candles)
    }

    /// Tencent also answers `jp7203` and `kr005930`, but only with quotes: its
    /// minute endpoint returns one point and its daily K-line one bar. Yahoo must
    /// therefore own both markets end to end, quotes included, or a chart would
    /// open on a source that has no history to draw.
    @Test("Composite: Tokyo and Seoul route to Yahoo for both quotes and charts", arguments: [
        SymbolID(market: .jp, code: "7203"),
        SymbolID(market: .kr, code: "005930"),
        SymbolID(market: .kq, code: "247540"),
    ])
    func compositeJapanKorea(symbol: SymbolID) async throws {
        let composite = CompositeProvider(providers: [BinanceProvider(), TencentProvider(), YahooProvider()])

        let quote = try #require(try await composite.quotes(for: [symbol]).first)
        Self.assertQuoteContract(quote)
        #expect(quote.sourceID == "yahoo")
        #expect(quote.currencyCode == symbol.market.currencyCode)

        let candles = try await composite.candles(for: symbol, period: .day, count: 30)
        Self.assertCandleContract(candles)
        #expect(candles.count > 1)
    }

    @Test("Composite: metals quote live and chart from history")
    func compositeMetals() async throws {
        let composite = CompositeProvider(providers: [BinanceProvider(), TencentProvider(), YahooProvider()])
        let gold = SymbolID(metal: .gold)

        let quote = try #require(try await composite.quotes(for: [gold]).first)
        Self.assertQuoteContract(quote)
        // Tencent quotes the international channel in real time; Yahoo's futures
        // feed is delayed, so it must not win the route.
        #expect(quote.sourceID == "tencent")

        let candles = try await composite.candles(for: gold, period: .day, count: 30)
        Self.assertCandleContract(candles)

        // "黄金" leads with spot — what the word means to someone asking the
        // price of gold — and the COMEX contract follows it.
        let results = try await composite.search("黄金")
        #expect(results.first?.symbol == SymbolID(metal: .goldSpot))
        #expect(results.dropFirst().first?.symbol == gold)
    }

    @Test("Sina: London spot quotes and history")
    func sinaSpot() async throws {
        let provider = SinaProvider()
        let spots = [SymbolID(metal: .goldSpot), SymbolID(metal: .silverSpot)]

        let quotes = try await provider.quotes(for: spots)
        #expect(quotes.count == spots.count)
        for quote in quotes {
            Self.assertQuoteContract(quote)
            #expect(quote.currencyCode == "USD")
        }

        for period in [CandlePeriod.day, .week, .month, .minute1, .minute5] {
            let candles = try await provider.candles(
                for: SymbolID(metal: .goldSpot), period: period, count: 30
            )
            Self.assertCandleContract(candles)
            #expect(candles.count <= 30)
        }
    }

    @Test("Composite: spot metals quote live and chart from the only source that has them")
    func compositeSpotMetals() async throws {
        let composite = CompositeProvider(providers: [
            BinanceProvider(), TencentProvider(), YahooProvider(), SinaProvider(),
        ])
        let spotGold = SymbolID(metal: .goldSpot)

        let quote = try #require(try await composite.quotes(for: [spotGold]).first)
        Self.assertQuoteContract(quote)
        // Tencent leads on quotes; Yahoo has no spot symbol and declines outright.
        #expect(quote.sourceID == "tencent")

        // Yahoo covers the metal market for candles but not spot, so this has to
        // fail over to Sina rather than returning a COMEX series.
        let candles = try await composite.candles(for: spotGold, period: .day, count: 30)
        Self.assertCandleContract(candles)

        // Spot and the COMEX contract are different instruments, not one with two
        // sources: they must not price the same.
        let comexQuote = try #require(try await composite.quotes(for: [SymbolID(metal: .gold)]).first)
        #expect(quote.price != comexQuote.price)
    }

    @Test("Sina: Shanghai futures quote in CNY with native intraday bars")
    func sinaShanghai() async throws {
        let provider = SinaProvider()
        let gold = SymbolID(metal: .shanghaiGold)

        let quotes = try await provider.quotes(for: [gold, SymbolID(metal: .shanghaiSilver)])
        #expect(quotes.count == 2)
        for quote in quotes {
            Self.assertQuoteContract(quote)
            #expect(quote.currencyCode == "CNY")
            // Domestic futures report exchange volume; the international channel does not.
            #expect((quote.volume ?? 0) > 0)
        }

        // Every intraday resolution has its own endpoint here, so none of them
        // are resampled; weekly and monthly still come from the daily series.
        for period in [CandlePeriod.minute1, .minute5, .minute15, .minute30, .hour1, .day, .week, .month] {
            let candles = try await provider.candles(for: gold, period: period, count: 20)
            Self.assertCandleContract(candles)
            #expect(candles.count <= 20)
        }
    }

    @Test("Composite: Shanghai metals route to the only source that carries them")
    func compositeShanghai() async throws {
        let composite = CompositeProvider(providers: [
            BinanceProvider(), TencentProvider(), YahooProvider(), SinaProvider(),
        ])
        let shanghaiGold = SymbolID(metal: .shanghaiGold)

        let quote = try #require(try await composite.quotes(for: [shanghaiGold]).first)
        Self.assertQuoteContract(quote)
        #expect(quote.sourceID == SinaProvider.providerID)
        #expect(quote.currencyCode == "CNY")

        let candles = try await composite.candles(for: shanghaiGold, period: .day, count: 30)
        Self.assertCandleContract(candles)

        // Shanghai quotes grams in CNY and COMEX ounces in USD: an order of
        // magnitude apart, which is exactly why they are separate markets.
        let comex = try #require(try await composite.quotes(for: [SymbolID(metal: .gold)]).first)
        #expect(comex.currencyCode == "USD")
        #expect(quote.price < comex.price)

        // Naming Shanghai leads with its spot contract; the futures one follows.
        let results = try await composite.search("沪金")
        #expect(results.first?.symbol == SymbolID(metal: .shanghaiGoldSpot))
        #expect(results.dropFirst().first?.symbol == shanghaiGold)
    }

    @Test("Composite: Shanghai spot gold is assembled from three sources")
    func compositeShanghaiSpot() async throws {
        let composite = CompositeProvider(providers: [
            BinanceProvider(), TencentProvider(), YahooProvider(), SinaProvider(),
            ShanghaiGoldExchangeProvider(), EastmoneyProvider(),
        ])
        let gold = SymbolID(metal: .shanghaiGoldSpot)

        // Quotes: Sina, the only source that carries this contract live.
        let quote = try #require(try await composite.quotes(for: [gold]).first)
        Self.assertQuoteContract(quote)
        #expect(quote.sourceID == SinaProvider.providerID)
        #expect(quote.currencyCode == "CNY")

        // Daily history: the exchange's own file, which Sina does not publish.
        for period in [CandlePeriod.day, .week, .month] {
            let candles = try await composite.candles(for: gold, period: period, count: 20)
            Self.assertCandleContract(candles)
        }

        // Spot and futures are separate instruments here too, and both are CNY
        // per gram — unlike the dollar-per-ounce pair.
        let futures = try #require(try await composite.quotes(for: [SymbolID(metal: .shanghaiGold)]).first)
        #expect(quote.price != futures.price)
        #expect(abs(quote.price - futures.price) / futures.price < 0.05)
    }

    /// Eastmoney is the only intraday source for this contract and it blocks
    /// bursts — sometimes with an empty body, sometimes by dropping the
    /// connection outright. Being unavailable is a state Pulse handles, so this
    /// checks the data whenever it answers and lets those two failures pass,
    /// while a decode or contract break still fails the suite.
    @Test("Eastmoney serves Shanghai spot intraday, or steps aside cleanly")
    func eastmoneyIntraday() async throws {
        let gold = SymbolID(metal: .shanghaiGoldSpot)
        do {
            let candles = try await EastmoneyProvider().candles(for: gold, period: .minute5, count: 20)
            Self.assertCandleContract(candles)
        } catch let error as ProviderError {
            switch error {
            case .rateLimited, .network:
                break
            case .badResponse, .clientError, .unsupported, .symbolNotFound:
                throw error
            }
        }
    }

    /// Sina is the only wired source for Shanghai metals, and it is an
    /// unofficial endpoint. The exchange publishes its own end-of-day file, so
    /// this checks Sina's continuous series against it: same session, same bars,
    /// and the same underlying contract. It is the alarm that fires if Sina ever
    /// changes what `AU0` means — something no amount of parsing care would catch.
    @Test("Sina's Shanghai gold agrees with the exchange's own daily file")
    func shanghaiGoldMatchesExchange() async throws {
        /// Product-summary rows carry empty strings where a contract row carries
        /// numbers, so every price decodes leniently.
        struct Number: Decodable {
            let value: Double?
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                value = (try? container.decode(Double.self))
                    ?? Double((try? container.decode(String.self)) ?? "")
            }
        }
        struct Instrument: Decodable {
            let PRODUCTID: String
            let OPENPRICE: Number
            let HIGHESTPRICE: Number
            let LOWESTPRICE: Number
            let CLOSEPRICE: Number
            let VOLUME: Number
        }
        struct DailyFile: Decodable { let o_curinstrument: [Instrument] }

        var beijing = Calendar(identifier: .gregorian)
        beijing.timeZone = Market.metalCN.timeZone
        let today = beijing.startOfDay(for: .now)

        // The newest completed session: today's bar may still be forming.
        let daily = try await SinaProvider().candles(
            for: SymbolID(metal: .shanghaiGold), period: .day, count: 5
        )
        let bar = try #require(daily.last { $0.time < today })

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Market.metalCN.timeZone
        formatter.dateFormat = "yyyyMMdd"
        let url = try #require(URL(
            string: "https://www.shfe.com.cn/data/tradedata/future/dailydata/kx\(formatter.string(from: bar.time)).dat"
        ))
        let data = try await HTTPClient().get(url, headers: ["Referer": "https://www.shfe.com.cn/"])
        let file = try JSONDecoder().decode(DailyFile.self, from: data)

        // Rows without a price are the product-level summary; the continuous
        // series follows whichever real contract carries the most volume.
        let gold = file.o_curinstrument.filter {
            $0.PRODUCTID.trimmingCharacters(in: .whitespaces) == "au_f"
                && ($0.OPENPRICE.value ?? 0) > 0
        }
        let official = try #require(gold.max { ($0.VOLUME.value ?? 0) < ($1.VOLUME.value ?? 0) })

        #expect(official.OPENPRICE.value == bar.open)
        #expect(official.HIGHESTPRICE.value == bar.high)
        #expect(official.LOWESTPRICE.value == bar.low)
        #expect(official.CLOSEPRICE.value == bar.close)
        #expect(official.VOLUME.value == bar.volume)
    }

    @Test("Composite: stock search")
    func compositeSearch() async throws {
        let composite = CompositeProvider(providers: [BinanceProvider(), TencentProvider(), YahooProvider()])
        let results = try await composite.search("AAPL")

        #expect(results.contains { $0.symbol == SymbolID(market: .us, code: "AAPL") })
    }
}

/// Source delay and refresh cadence are different promises, and conflating them
/// is what makes a polled "realtime" price feel wrong: it is current when read,
/// but it only moves when Pulse asks again.
@Suite("Quote refresh cadence")
struct QuoteCadenceTests {
    @Test("A pushing source has no cadence to report")
    func pushingSource() {
        let streaming = ProviderDescriptor(
            id: "push", name: "Push", markets: [.us],
            capabilities: [.quotes, .streaming]
        )
        #expect(streaming.pollingCadenceSeconds(interval: 15) == nil)
    }

    @Test("A polled source reports the interval it is polled at")
    func polledSource() {
        let polled = ProviderDescriptor(
            id: "poll", name: "Poll", markets: [.metal], capabilities: [.quotes]
        )
        #expect(polled.pollingCadenceSeconds(interval: 15) == 15)
        #expect(polled.pollingCadenceSeconds(interval: 60) == 60)
        // Sub-second polling still reads as one second rather than zero.
        #expect(polled.pollingCadenceSeconds(interval: 0.4) == 1)
        #expect(polled.pollingCadenceSeconds(interval: 0) == nil)
    }

    @Test("The wired sources split the way the UI claims")
    func wiredSources() {
        #expect(BinanceProvider().descriptor.pollingCadenceSeconds(interval: 15) == nil)
        for descriptor in [
            TencentProvider().descriptor, YahooProvider().descriptor,
            SinaProvider().descriptor, ShanghaiGoldExchangeProvider().descriptor,
            EastmoneyProvider().descriptor,
        ] {
            #expect(descriptor.pollingCadenceSeconds(interval: 15) == 15,
                    "\(descriptor.id) should report a cadence")
        }
    }
}
