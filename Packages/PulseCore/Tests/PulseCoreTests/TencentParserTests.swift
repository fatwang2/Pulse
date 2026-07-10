import Foundation
import Testing
@testable import PulseCore

@Suite("Tencent quote parsing")
struct TencentParserTests {
    /// Excerpt from a real API response (intraday, 2026-07-03)
    static let fixture = """
    v_sh600519="1~贵州茅台~600519~1191.53~1203.00~1205.24~19108~8113~10970~1191.53~3~1191.51~3~1191.48~8~1191.43~1~1191.35~1~1192.80~1~1192.84~3~1192.85~2~1192.90~1~1193.18~1~~20260703112400~-11.47~-0.95~1210.14~1190.50~1191.53/19108/2293596002~19108~229360~0.15~18.01~~1210.14~1190.50~1.63~14895.10~14895.10~6.40~1323.30~1082.70~0.80~8~1200.32~13.67~18.09~~~0.34~229359.6002~0.0000~0~ ~GP-A~-11.68~1.96~4.37~30.53~26.78~1539.98~1151.01~0.38~-3.91~-16.79~1250081601~1250081601~33.33~-15.43~1250081601";
    """

    @Test("Parses an A-share snapshot")
    func parseAShare() throws {
        let symbol = SymbolID(market: .sh, code: "600519")
        let quotes = TencentProvider.parseQuotes(text: Self.fixture, mapping: ["sh600519": symbol])
        let quote = try #require(quotes.first)

        #expect(quote.symbol == symbol)
        #expect(quote.name == "贵州茅台")
        #expect(quote.price == 1191.53)
        #expect(quote.previousClose == 1203.00)
        #expect(quote.open == 1205.24)
        #expect(quote.high == 1210.14)
        #expect(quote.low == 1190.50)
        #expect(quote.currencyCode == "CNY")
        // The derived change percent matches the API's own figure (-0.95%)
        #expect(abs(quote.changePercent - -0.95) < 0.01)
        // A-share volume (field 36) is in lots and must be converted to shares; cross-checked against the combined field "1191.53/19108/2293596002"
        let volume = try #require(quote.volume)
        #expect(abs(volume - 1_910_800.0) < 0.5)
        // Turnover (field 37) is in units of 10,000 CNY
        let turnover = try #require(quote.turnover)
        #expect(abs(turnover - 2_293_600_000.0) < 0.5)
    }

    @Test("Timestamps parsed in the exchange time zone")
    func timestamp() throws {
        let date = try #require(TencentProvider.parseTimestamp("20260703112400", timeZone: Market.sh.timeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.sh.timeZone
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(comps.year == 2026)
        #expect(comps.month == 7)
        #expect(comps.day == 3)
        #expect(comps.hour == 11)
        #expect(comps.minute == 24)

        // HK/US slash and dash formats must also parse
        #expect(TencentProvider.parseTimestamp("2026/07/02 16:08:00", timeZone: Market.hk.timeZone) != nil)
        #expect(TencentProvider.parseTimestamp("2026-07-02 16:00:01", timeZone: Market.us.timeZone) != nil)
    }

    @Test("A-share minute series parses and aggregates into five-minute bars")
    func minuteCandles() throws {
        let rows = [
            "0930 10.00 10 1000.00",
            "0931 11.00 13 1300.00",
            "0934 9.00 20 2000.00",
            "bad row",
            "0935 12.00 25 2500.00",
        ]

        let oneMinute = TencentProvider.parseMinuteCandles(
            date: "20260710", rows: rows, market: .sh, period: .minute1
        )
        #expect(oneMinute.count == 4)
        #expect(oneMinute.map(\.close) == [10, 11, 9, 12])
        #expect(oneMinute.compactMap(\.volume) == [1000, 300, 700, 500])

        let fiveMinute = TencentProvider.parseMinuteCandles(
            date: "20260710", rows: rows, market: .sh, period: .minute5
        )
        #expect(fiveMinute.count == 2)
        let first = try #require(fiveMinute.first)
        #expect(first.open == 10)
        #expect(first.high == 11)
        #expect(first.low == 9)
        #expect(first.close == 9)
        #expect(first.volume == 2000)
        #expect(fiveMinute.last?.close == 12)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Market.sh.timeZone
        #expect(calendar.component(.hour, from: first.time) == 9)
        #expect(calendar.component(.minute, from: first.time) == 30)

        let now = try #require(TencentProvider.parseTimestamp("20260710104324", timeZone: Market.sh.timeZone))
        let provisional = TencentProvider.parseMinuteCandles(
            date: "20260710",
            rows: ["1044 12.50 30 3000.00"],
            market: .sh,
            period: .minute1,
            now: now
        )
        #expect(provisional.first?.time == now)
    }

    @Test("Tencent candle coverage is limited to A-share intraday periods")
    func candleCoverage() {
        let descriptor = TencentProvider().descriptor
        #expect(descriptor.supports(candles: .minute1, in: .sh))
        #expect(descriptor.supports(candles: .minute5, in: .sz))
        #expect(!descriptor.supports(candles: .day, in: .sh))
        #expect(!descriptor.supports(candles: .minute1, in: .hk))
    }

    /// Excerpt from a real smartbox response (query: Tencent's Chinese name); the real API returns names in \uXXXX escaped form
    static let smartboxFixture = #"v_hint="sh~000847~腾讯济安~txja~ZS^hk~00700~腾讯控股~txkg~GP^us~tcehy.ps~腾讯控股(adr)~txkgadr~GP^us~tme.n~腾讯音乐~txyl~GP^bk~123456~板块~bk~BK""#

    @Test("smartbox search parsing")
    func parseSearch() throws {
        let results = TencentProvider.parseSearch(text: Self.smartboxFixture)

        // Sector (bk) entries should be filtered out
        #expect(results.count == 4)

        let tencent = try #require(results.first { $0.symbol == SymbolID(market: .hk, code: "700") })
        #expect(tencent.name == "腾讯控股")
        #expect(tencent.type == .equity)

        // US codes have their exchange suffix stripped and are uppercased
        #expect(results.contains { $0.symbol == SymbolID(market: .us, code: "TME") })
        #expect(results.contains { $0.symbol == SymbolID(market: .us, code: "TCEHY") })

        // Index type recognition
        let index = try #require(results.first { $0.symbol == SymbolID(market: .sh, code: "000847") })
        #expect(index.type == .index)
    }

    @Test("Unicode unescaping")
    func unescape() {
        // "\\u817e\\u8baf..." is the literal escaped form returned by the real API; it should decode to the Chinese name
        #expect(TencentProvider.unescapeUnicode("\\u817e\\u8baf\\u63a7\\u80a1") == "腾讯控股")
        #expect(TencentProvider.unescapeUnicode("AAPL") == "AAPL")
        #expect(TencentProvider.unescapeUnicode("\\u817e\\u8baf\\u63a7\\u80a1(adr)") == "腾讯控股(adr)")
    }

    @Test("smartbox escaped names parsed end to end")
    func parseSearchEscaped() throws {
        // The name field is \uXXXX-escaped (matching the real API) and should decode back to Chinese
        let fixture = "v_hint=\"hk~00700~\\u817e\\u8baf\\u63a7\\u80a1~txkg~GP\""
        let results = TencentProvider.parseSearch(text: fixture)
        let tencent = try #require(results.first)
        #expect(tencent.name == "腾讯控股")
        #expect(tencent.symbol == SymbolID(market: .hk, code: "700"))
    }

    @Test("Bad lines and unrequested keys are ignored")
    func garbage() {
        let text = """
        v_sh600519="1~贵州茅台~600519";
        v_unknown="1~x~y~1.0~1.0~1.0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~20260703112400~0~0~1~1~x~0~0~0";
        garbage line without equals
        """
        let quotes = TencentProvider.parseQuotes(
            text: text,
            mapping: ["sh600519": SymbolID(market: .sh, code: "600519")]
        )
        #expect(quotes.isEmpty)
    }
}
