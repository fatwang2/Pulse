import Foundation
import Testing
@testable import PulseCore

@Suite("Naver parsing")
struct NaverParserTests {
    /// Trimmed from a live response. Samsung is rising, KB금융 falling — Naver
    /// signs the move itself rather than flagging a direction.
    private static let quotePayload = Data("""
    {"pollingInterval":7000,"datas":[
      {"itemCode":"005930","stockName":"삼성전자",
       "stockExchangeType":{"code":"KS","nameEng":"KOSPI","delayTime":0},
       "closePrice":"268,500","compareToPreviousClosePrice":"21,000",
       "compareToPreviousPrice":{"code":"2","text":"상승","name":"RISING"},
       "openPrice":"257,000","highPrice":"273,000","lowPrice":"252,500",
       "accumulatedTradingVolume":"14,990,890","accumulatedTradingValue":"3조 9,640억",
       "marketStatus":"OPEN","localTradedAt":"2026-08-20T12:12:37.828638+09:00",
       "closePriceRaw":268500,"compareToPreviousClosePriceRaw":21000,
       "openPriceRaw":257000,"highPriceRaw":273000,"lowPriceRaw":252500,
       "accumulatedTradingVolumeRaw":14990890,"accumulatedTradingValueRaw":3964004000000},
      {"itemCode":"105560","stockName":"KB금융",
       "stockExchangeType":{"code":"KS","nameEng":"KOSPI","delayTime":0},
       "closePriceRaw":161800,"compareToPreviousClosePriceRaw":-4600,
       "openPriceRaw":166000,"highPriceRaw":166400,"lowPriceRaw":161000,
       "accumulatedTradingVolumeRaw":1234567,
       "localTradedAt":"2026-08-20T12:12:24+09:00"},
      {"itemCode":"247540","stockName":"에코프로비엠",
       "stockExchangeType":{"code":"KQ","nameEng":"KOSDAQ","delayTime":0},
       "closePriceRaw":113800,"compareToPreviousClosePriceRaw":4000,
       "localTradedAt":"2026-08-20T12:11:01.056878+09:00"}
    ]}
    """.utf8)

    private static let requested: [String: SymbolID] = [
        "005930": SymbolID(market: .kr, code: "005930"),
        "105560": SymbolID(market: .kr, code: "105560"),
        "247540": SymbolID(market: .kq, code: "247540"),
    ]

    @Test("A batch answer maps every row back to the symbol that asked for it")
    func batchQuotes() throws {
        let quotes = try NaverProvider.parseQuotes(Self.quotePayload, requested: Self.requested)
        #expect(quotes.count == 3)

        let samsung = try #require(quotes.first { $0.symbol.code == "005930" })
        #expect(samsung.name == "삼성전자")
        #expect(samsung.price == 268_500)
        #expect(samsung.previousClose == 247_500)   // 268,500 − 21,000
        #expect(samsung.open == 257_000)
        #expect(samsung.high == 273_000)
        #expect(samsung.low == 252_500)
        #expect(samsung.volume == 14_990_890)
        #expect(samsung.turnover == 3_964_004_000_000)
        #expect(samsung.currencyCode == "KRW")
    }

    /// A decline arrives as a negative change, so the reference price is above
    /// the current one. Reading it unsigned would invert the day's move.
    @Test("A falling stock keeps its previous close above its price")
    func decliningQuote() throws {
        let quotes = try NaverProvider.parseQuotes(Self.quotePayload, requested: Self.requested)
        let kb = try #require(quotes.first { $0.symbol.code == "105560" })
        #expect(kb.price == 161_800)
        #expect(kb.previousClose == 166_400)
        #expect(kb.previousClose > kb.price)
    }

    @Test("Each row keeps the board the caller asked with")
    func boardsSurvive() throws {
        let quotes = try NaverProvider.parseQuotes(Self.quotePayload, requested: Self.requested)
        #expect(quotes.first { $0.symbol.code == "247540" }?.symbol.market == .kq)
        #expect(quotes.first { $0.symbol.code == "005930" }?.symbol.market == .kr)
    }

    /// An unknown code is answered with an empty list and HTTP 200, so nothing
    /// is parsed rather than something being invented.
    @Test("An unknown code yields no quote instead of an error")
    func unknownCode() throws {
        let empty = Data(#"{"pollingInterval":70000,"datas":[],"time":"20260820121208"}"#.utf8)
        #expect(try NaverProvider.parseQuotes(empty, requested: Self.requested).isEmpty)
    }

    @Test("Timestamps parse with or without sub-second digits")
    func timestamps() throws {
        let withFraction = try #require(NaverProvider.timestamp(from: "2026-08-20T12:12:37.828638+09:00"))
        let without = try #require(NaverProvider.timestamp(from: "2026-08-20T12:12:24+09:00"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.kr.timeZone
        #expect(calendar.component(.hour, from: withFraction) == 12)
        #expect(calendar.component(.second, from: withFraction) == 37)
        #expect(calendar.component(.second, from: without) == 24)
        #expect(NaverProvider.timestamp(from: "nonsense") == nil)
    }

    // MARK: - Search

    /// The same endpoint answers with Hong Kong listings for a Latin query, and
    /// lists a dozen Korean indices Pulse does not model.
    private static let searchPayload = Data("""
    {"query":"삼성","items":[
      {"code":"005930","name":"삼성전자","typeCode":"KOSPI","typeName":"코스피","category":"stock","nationCode":"KOR"},
      {"code":"247540","name":"에코프로비엠","typeCode":"KOSDAQ","typeName":"코스닥","category":"stock","nationCode":"KOR"},
      {"code":"0193T0","name":"KODEX SK하이닉스","typeCode":"KOSPI","typeName":"코스피","category":"stock","nationCode":"KOR"},
      {"code":"02812","name":"Samsung CSI China Dragon Internet ETF","typeCode":"HONG_KONG","typeName":"홍콩","category":"stock","nationCode":"HKG"},
      {"code":"KOSPI","name":"코스피","typeCode":"INDEX","typeName":"지수","category":"index"},
      {"code":"KPI200","name":"코스피 200","typeCode":"INDEX","typeName":"지수","category":"index"},
      {"code":"FUT","name":"코스피 200 선물","typeCode":"FUTURES","typeName":"지수","category":"index"}
    ]}
    """.utf8)

    @Test("Search resolves the board and drops what Pulse does not model")
    func search() throws {
        let results = try NaverProvider.parseSearch(Self.searchPayload)
        let symbols = results.map(\.symbol)

        #expect(symbols.contains(SymbolID(market: .kr, code: "005930")))
        #expect(symbols.contains(SymbolID(market: .kq, code: "247540")))
        #expect(symbols.contains(SymbolID(index: .kospi)))

        // Foreign listings, the sibling indices and the futures are all dropped.
        #expect(!symbols.contains { $0.code == "02812" })
        #expect(!symbols.contains { $0.code == "KPI200" || $0.code == "FUT" })
        #expect(results.count == 4)
    }

    /// Korean codes are not always six digits: newer ETF share classes carry a
    /// letter, which is why the code is stored verbatim rather than normalized.
    @Test("A code containing a letter survives")
    func alphanumericCode() throws {
        let results = try NaverProvider.parseSearch(Self.searchPayload)
        let etf = try #require(results.first { $0.symbol.code == "0193T0" })
        #expect(etf.symbol.market == .kr)
        #expect(etf.name == "KODEX SK하이닉스")
    }

    // MARK: - Candles

    @Test("Daily bars carry OHLC in the order Naver writes them")
    func dailyCandles() throws {
        let payload = Data("""
        [{"localDate":"20260102","closePrice":128500.0,"openPrice":120200.0,"highPrice":128500.0,
          "lowPrice":120200.0,"accumulatedTradingVolume":30463279,"foreignRetentionRate":52.37},
         {"localDate":"20260105","closePrice":138100.0,"openPrice":129000.0,"highPrice":139000.0,
          "lowPrice":128000.0,"accumulatedTradingVolume":41000000}]
        """.utf8)
        let candles = try NaverProvider.parseCandles(payload, intraday: false)
        #expect(candles.count == 2)
        #expect(candles[0].open == 120_200)
        #expect(candles[0].high == 128_500)
        #expect(candles[0].low == 120_200)
        #expect(candles[0].close == 128_500)
        #expect(candles[0].volume == 30_463_279)
        #expect(candles[0].time < candles[1].time)
    }

    /// The minute line spells a bar's close `currentPrice`; reading `closePrice`
    /// alone would drop every intraday bar.
    @Test("Minute bars take their close from currentPrice")
    func minuteCandles() throws {
        let payload = Data("""
        [{"localDateTime":"20260820090000","currentPrice":256500.0,"openPrice":257000.0,
          "highPrice":258500.0,"lowPrice":256500.0,"accumulatedTradingVolume":949560},
         {"localDateTime":"20260820090100","currentPrice":255000.0,"openPrice":256500.0,
          "highPrice":257000.0,"lowPrice":254500.0,"accumulatedTradingVolume":202894}]
        """.utf8)
        let candles = try NaverProvider.parseCandles(payload, intraday: true)
        #expect(candles.count == 2)
        #expect(candles[0].close == 256_500)
        #expect(candles[0].open == 257_000)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.kr.timeZone
        #expect(calendar.component(.hour, from: candles[0].time) == 9)
        #expect(calendar.component(.minute, from: candles[1].time) == 1)
    }

    @Test("Five-minute bars fold out of the minute line on Seoul's clock")
    func resampling() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.kr.timeZone
        let open = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 20, hour: 9, minute: 0)
        ))
        let minutes = (0..<10).map { i in
            Candle(time: open.addingTimeInterval(Double(i) * 60),
                   open: 100 + Double(i), high: 110 + Double(i), low: 90 + Double(i),
                   close: 105 + Double(i), volume: 10)
        }
        let bars = CandleResampler.resample(minutes, into: .minute5, timeZone: Market.kr.timeZone)
        #expect(bars.count == 2)
        #expect(bars[0].open == 100)      // first bar of the bucket
        #expect(bars[0].close == 109)     // last bar of the bucket
        #expect(bars[0].high == 114)
        #expect(bars[0].low == 90)
        #expect(bars[0].volume == 50)
        // The bucket starts on the session open, not an hour either side of it.
        #expect(calendar.component(.hour, from: bars[0].time) == 9)
        #expect(calendar.component(.minute, from: bars[0].time) == 0)
        #expect(calendar.component(.minute, from: bars[1].time) == 5)
    }

    @Test("A bar count becomes a window wide enough to hold it")
    func lookback() {
        // A Seoul session is 390 one-minute bars, so 400 of them need two days.
        #expect(NaverProvider.lookbackDays(for: .minute1, count: 400) >= 4)
        // Sixty hourly bars is ten sessions' worth of minutes.
        #expect(NaverProvider.lookbackDays(for: .hour1, count: 60) >= 12)
        #expect(NaverProvider.lookbackDays(for: .day, count: 250) >= 250)
        #expect(NaverProvider.lookbackDays(for: .month, count: 24) >= 720)
    }

    @Test("Naver addresses instruments by bare code and indices by name")
    func addressing() {
        #expect(NaverProvider.naverCode(for: SymbolID(market: .kr, code: "005930")) == "005930")
        #expect(NaverProvider.naverCode(for: SymbolID(market: .kq, code: "247540")) == "247540")
        #expect(NaverProvider.naverCode(for: SymbolID(index: .kospi)) == "KOSPI")
        // Nothing outside Korea is addressable here.
        #expect(NaverProvider.naverCode(for: SymbolID(market: .jp, code: "7203")) == nil)
        #expect(NaverProvider.naverCode(for: SymbolID(market: .us, code: "AAPL")) == nil)
        #expect(NaverProvider.naverCode(for: SymbolID(index: .nikkei225)) == nil)
    }
}
