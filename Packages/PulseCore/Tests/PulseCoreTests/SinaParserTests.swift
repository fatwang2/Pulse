import Foundation
import Testing
@testable import PulseCore

@Suite("Sina quote and history parsing")
struct SinaParserTests {
    /// Excerpt from a real hq.sinajs.cn response (2026-08-20). Field 1 is the
    /// previous close here, where Tencent puts the change percent — the shared
    /// parser reads neither.
    static let spotFixture = """
    var hq_str_hf_XAU="4490.41,4334.170,4490.41,4490.76,4499.23,4324.66,01:23:00,4334.17,4336.13,0,0,0,2026-08-20,伦敦金（现货黄金）";
    var hq_str_hf_XAG="63.18,63.30,63.18,63.23,63.45,62.16,01:23:00,63.30,63.12,0,0,0,2026-08-20,伦敦银（现货白银）";
    """

    @Test("Parses a London spot snapshot")
    func parseSpot() throws {
        let gold = SymbolID(metal: .goldSpot)
        let silver = SymbolID(metal: .silverSpot)
        let quotes = SinaProvider.parseQuotes(
            text: Self.spotFixture,
            mapping: ["hf_XAU": gold, "hf_XAG": silver]
        )
        #expect(quotes.count == 2)

        let quote = try #require(quotes.first { $0.symbol == gold })
        #expect(quote.name == "伦敦金（现货黄金）")
        #expect(quote.price == 4490.41)
        #expect(quote.previousClose == 4334.17)
        #expect(quote.open == 4336.13)
        #expect(quote.high == 4499.23)
        #expect(quote.low == 4324.66)
        #expect(quote.currencyCode == "USD")
        #expect(quote.volume == nil)

        var beijing = Calendar(identifier: .gregorian)
        beijing.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = beijing.dateComponents([.day, .hour, .minute], from: quote.timestamp)
        #expect(parts == DateComponents(day: 20, hour: 1, minute: 23))
    }

    @Test("Both providers' international payloads parse identically")
    func sharedPayloadShape() throws {
        let gold = SymbolID(metal: .gold)
        // Same instrument, same instant, one from each source: only field 1 differs.
        let tencent = InternationalFuturesQuote.parse(
            payload: "4413.61,-0.16,4412.90,4413.30,4417.20,4378.00,16:53:00,4420.60,4391.40,0,2,2,2026-08-19,纽约黄金",
            symbol: gold
        )
        let sina = InternationalFuturesQuote.parse(
            payload: "4413.61,4420.600,4412.90,4413.30,4417.20,4378.00,16:53:00,4420.60,4391.40,0,2,2,2026-08-19,纽约黄金",
            symbol: gold
        )
        #expect(tencent?.price == sina?.price)
        #expect(tencent?.previousClose == sina?.previousClose)
        #expect(tencent?.timestamp == sina?.timestamp)
    }

    @Test("Strips the anti-hotlink prefix around the JSONP payload")
    func jsonpUnwrapping() throws {
        let raw = Data("""
        /*<script>location.href='//sina.com';</script>*/
        x([{"date":"2026-08-19","open":"1","high":"2","low":"0.5","close":"1.5","volume":"0"}]);
        """.utf8)
        let payload = try SinaProvider.jsonPayload(from: raw)
        let candles = try SinaProvider.parseDailyCandles(payload)
        #expect(candles.count == 1)
        #expect(candles[0].close == 1.5)
        // Sina reports 0 for this channel; that is "not reported", not "no trading".
        #expect(candles[0].volume == nil)
    }

    /// The opening row of a minute line carries four extra leading fields, so
    /// both shapes have to read from the end.
    @Test("Reads both minute-line row shapes")
    func minuteLineShapes() throws {
        let raw = Data("""
        x({"minLine_1d":[
          ["2026-08-19","4334.170","LIFFE","","06:00","4335.890","0","0","4336.458","2026-08-19 06:00:00"],
          ["06:01","4338.380","0","0","4336.729","2026-08-19 06:01:00"],
          ["01:50","4488.100","0","0","4386.466","2026-08-20 01:50:00"]
        ]});
        """.utf8)
        let candles = try SinaProvider.parseMinuteCandles(try SinaProvider.jsonPayload(from: raw))
        #expect(candles.map(\.close) == [4335.89, 4338.38, 4488.10])
        // A minute line is one price per minute, so each bar is flat.
        #expect(candles[0].open == candles[0].close)
        #expect(candles.map(\.time) == candles.map(\.time).sorted())
    }

    @Test("Resamples the two published series into the other periods")
    func aggregation() throws {
        var beijing = Calendar(identifier: .gregorian)
        beijing.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day = try #require(beijing.date(from: DateComponents(year: 2026, month: 8, day: 17)))

        // Five consecutive days spanning a week boundary (17th is a Monday).
        let daily = (0..<5).map { offset in
            Candle(
                time: beijing.date(byAdding: .day, value: offset, to: day)!,
                open: Double(10 + offset), high: Double(12 + offset),
                low: Double(9 + offset), close: Double(11 + offset), volume: 100
            )
        }
        let weekly = SinaProvider.aggregate(daily, into: .week)
        #expect(weekly.count == 1)
        #expect(weekly[0].open == 10)
        #expect(weekly[0].close == 15)
        #expect(weekly[0].high == 16)
        #expect(weekly[0].low == 9)
        #expect(weekly[0].volume == 500)

        // Daily and one-minute bars are what Sina actually publishes: untouched.
        #expect(SinaProvider.aggregate(daily, into: .day) == daily)

        let minutes = (0..<12).map { offset in
            Candle(
                time: day.addingTimeInterval(Double(offset) * 60),
                open: 100, high: 100, low: 100, close: Double(100 + offset)
            )
        }
        let fiveMinute = SinaProvider.aggregate(minutes, into: .minute5)
        #expect(fiveMinute.count == 3)
        #expect(fiveMinute.map(\.close) == [104, 109, 111])
        #expect(fiveMinute[0].time == day)
    }

    /// Excerpt from a real hq.sinajs.cn domestic response (2026-08-20 02:30,
    /// the night session's close).
    static let domesticFixture = """
    var hq_str_nf_AU0="黄金连续,023000,965.000,974.520,960.100,0.000,969.480,969.500,969.500,0.000,949.260,2,1,208994.000,248473,沪,黄金,2026-08-20,1,,,,,,,,,968.207,0.000,0";
    """

    @Test("Parses a Shanghai futures snapshot against the previous settlement")
    func parseDomestic() throws {
        let gold = SymbolID(metal: .shanghaiGold)
        let quote = try #require(
            SinaProvider.parseQuotes(text: Self.domesticFixture, mapping: ["nf_AU0": gold]).first
        )

        #expect(quote.name == "黄金连续")
        #expect(quote.price == 969.5)
        // The close field reads 0 on this channel; a futures day is measured
        // against the previous settlement instead.
        #expect(quote.previousClose == 949.26)
        #expect(abs(quote.changePercent - 2.13) < 0.01)
        #expect(quote.open == 965.0)
        #expect(quote.high == 974.52)
        #expect(quote.low == 960.1)
        #expect(quote.volume == 248_473)
        // Shanghai prices in CNY per gram, not USD per ounce.
        #expect(quote.currencyCode == "CNY")

        var beijing = Calendar(identifier: .gregorian)
        beijing.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = beijing.dateComponents([.day, .hour, .minute], from: quote.timestamp)
        #expect(parts == DateComponents(day: 20, hour: 2, minute: 30))
    }

    @Test("Domestic daily and minute rows share one shape")
    func parseDomesticCandles() throws {
        let daily = Data("""
        x([{"d":"2026-08-19","o":"956.560","h":"957.880","l":"940.820","c":"945.560","v":"285920","p":"195748","s":"949.260"}]);
        """.utf8)
        let bars = try SinaProvider.parseDomesticCandles(
            try SinaProvider.jsonPayload(from: daily), dateFormat: "yyyy-MM-dd"
        )
        #expect(bars.count == 1)
        #expect(bars[0].close == 945.56)
        #expect(bars[0].volume == 285_920)

        let minutes = Data("""
        x([{"d":"2026-08-20 02:30:00","o":"970.460","h":"970.680","l":"969.000","c":"969.520","v":"77","p":"208994"}]);
        """.utf8)
        let intraday = try SinaProvider.parseDomesticCandles(
            try SinaProvider.jsonPayload(from: minutes), dateFormat: "yyyy-MM-dd HH:mm:ss"
        )
        #expect(intraday.count == 1)
        #expect(intraday[0].close == 969.52)
    }

    @Test("Sina covers the metal market only, quotes and history")
    func coverage() {
        let descriptor = SinaProvider().descriptor
        #expect(descriptor.markets == [.metal, .metalCN])
        #expect(descriptor.supports(.quotes, in: .metal))
        #expect(descriptor.supports(candles: .day, in: .metal))
        #expect(!descriptor.supports(.quotes, in: .us))
        #expect(descriptor.delay[.metal] == 0)

        #expect(SinaProvider.sinaSymbol(for: SymbolID(metal: .goldSpot)) == "hf_XAU")
        #expect(SinaProvider.sinaSymbol(for: SymbolID(metal: .silverSpot)) == "hf_XAG")
        #expect(SinaProvider.sinaSymbol(for: SymbolID(metal: .gold)) == "hf_GC")
        // Domestic futures answer on a different channel with its own payload.
        #expect(SinaProvider.sinaSymbol(for: SymbolID(metal: .shanghaiGold)) == "nf_AU0")
        #expect(SinaProvider.sinaSymbol(for: SymbolID(metal: .shanghaiSilver)) == "nf_AG0")
        #expect(descriptor.supports(candles: .minute5, in: .metalCN))
        #expect(SinaProvider.sinaSymbol(for: SymbolID(market: .us, code: "AAPL")) == nil)
    }
}
