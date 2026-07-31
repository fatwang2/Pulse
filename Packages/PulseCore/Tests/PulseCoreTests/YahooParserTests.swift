import Foundation
import Testing
@testable import PulseCore

@Suite("Yahoo response parsing")
struct YahooParserTests {
    static let chartFixture = Data("""
    {"chart":{"result":[{"meta":{"currency":"HKD","symbol":"0700.HK","exchangeName":"HKG",
    "regularMarketPrice":437.2,"chartPreviousClose":444.8,"previousClose":444.8,
    "regularMarketDayHigh":440.0,"regularMarketDayLow":435.0,"regularMarketVolume":12345678,
    "regularMarketTime":1783048138,"shortName":"TENCENT","longName":"Tencent Holdings Limited"},
    "timestamp":[1782867600,1782954000,1783040400],
    "indicators":{"quote":[{"open":[440.0,442.0,null],"high":[445.0,446.0,440.0],
    "low":[438.0,440.0,435.0],"close":[444.8,441.0,437.2],"volume":[1000,2000,3000]}]}}],
    "error":null}}
    """.utf8)

    @Test("chart metadata maps to Quote")
    func chartMeta() throws {
        let decoded = try YahooProvider.decode(ChartResponse.self, from: Self.chartFixture)
        let meta = try #require(decoded.chart.result?.first?.meta)
        #expect(meta.regularMarketPrice == 437.2)
        #expect(meta.previousClose == 444.8)
        #expect(meta.longName == "Tencent Holdings Limited")
        #expect(meta.currency == "HKD")
    }

    @Test("Candle arrays parsed, null entries skipped")
    func candles() throws {
        let decoded = try YahooProvider.decode(ChartResponse.self, from: Self.chartFixture)
        let result = try #require(decoded.chart.result?.first)
        let timestamps = try #require(result.timestamp)
        let ohlc = try #require(result.indicators.quote?.first)

        var candles: [Candle] = []
        for (i, ts) in timestamps.enumerated() {
            guard let open = ohlc.open?[safe: i] ?? nil,
                  let high = ohlc.high?[safe: i] ?? nil,
                  let low = ohlc.low?[safe: i] ?? nil,
                  let close = ohlc.close?[safe: i] ?? nil else { continue }
            candles.append(Candle(time: Date(timeIntervalSince1970: TimeInterval(ts)),
                                  open: open, high: high, low: low, close: close))
        }
        // The third bar's open is null and should be skipped
        #expect(candles.count == 2)
        #expect(candles[0].close == 444.8)
        #expect(candles[1].isUp == false)
    }

    @Test("API error object is recognized")
    func apiError() throws {
        let data = Data(#"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found"}}}"#.utf8)
        let decoded = try YahooProvider.decode(ChartResponse.self, from: data)
        #expect(decoded.chart.error?.code == "Not Found")
    }

    @Test("Extended sessions compare against the latest regular close")
    func extendedSessionReferenceClose() {
        #expect(YahooProvider.referenceClose(
            for: .preMarket,
            regularPrice: 308.63,
            previousClose: 294.38,
            chartPreviousClose: 294.38
        ) == 308.63)
        #expect(YahooProvider.referenceClose(
            for: .postMarket,
            regularPrice: 308.63,
            previousClose: 294.38,
            chartPreviousClose: 294.38
        ) == 308.63)
        #expect(YahooProvider.referenceClose(
            for: .regular,
            regularPrice: 308.63,
            previousClose: 294.38,
            chartPreviousClose: nil
        ) == 294.38)
    }

    @Test("Extended sessions carry the last regular session's own result")
    func extendedSessionRegularClose() throws {
        // Post-market: today's close (333.43) against yesterday's (338.19).
        let post = try #require(YahooProvider.regularSessionClose(
            for: .postMarket,
            regularPrice: 333.43,
            previousClose: 338.19,
            chartPreviousClose: 340.08
        ))
        #expect(post.price == 333.43)
        #expect(post.previousClose == 338.19)
        #expect(post.change.map { abs($0 - -4.76) < 0.0001 } == true)

        // Pre-market: the last regular close is yesterday's; its reference is
        // the close before the 2-day chart window.
        let pre = try #require(YahooProvider.regularSessionClose(
            for: .preMarket,
            regularPrice: 338.19,
            previousClose: 338.19,
            chartPreviousClose: 340.08
        ))
        #expect(pre.price == 338.19)
        #expect(pre.previousClose == 340.08)

        // In or after regular hours without an extended print, there is no
        // separate "yesterday" to attach.
        #expect(YahooProvider.regularSessionClose(
            for: .regular, regularPrice: 333.43, previousClose: 338.19, chartPreviousClose: 340.08
        ) == nil)
        #expect(YahooProvider.regularSessionClose(
            for: .closed, regularPrice: 333.43, previousClose: 338.19, chartPreviousClose: 340.08
        ) == nil)
    }

    @Test("Regular session close derives change and guards a missing reference")
    func regularSessionCloseDerivations() {
        let known = Quote.RegularSessionClose(price: 110, previousClose: 100)
        #expect(known.change == 10)
        #expect(known.changePercent == 10)

        let unknown = Quote.RegularSessionClose(price: 110)
        #expect(unknown.change == nil)
        #expect(unknown.changePercent == nil)
    }

    @Test("Intraday candle resolutions map to provider-native intervals")
    func intradayChartParams() {
        #expect(YahooProvider.chartParams(for: .minute5).interval == "5m")
        #expect(YahooProvider.chartParams(for: .minute5).range == "5d")
        #expect(YahooProvider.chartParams(for: .minute15).interval == "15m")
        #expect(YahooProvider.chartParams(for: .minute30).interval == "30m")
        #expect(YahooProvider.chartParams(for: .hour1).interval == "60m")

        #expect(BinanceProvider.interval(for: .minute5) == "5m")
        #expect(BinanceProvider.interval(for: .minute15) == "15m")
        #expect(BinanceProvider.interval(for: .minute30) == "30m")
        #expect(BinanceProvider.interval(for: .hour1) == "1h")
    }
}
