import Foundation
import Testing
@testable import PulseCore

/// Au99.99 is the price most people in China mean by "黄金", and it is assembled
/// from three sources: Sina quotes it, the exchange publishes its daily history,
/// and Eastmoney fills in intraday. Each leg parses differently.
@Suite("Shanghai spot gold")
struct ShanghaiSpotGoldTests {
    private let gold = SymbolID(metal: .shanghaiGoldSpot)

    /// Excerpt from a real hq.sinajs.cn response (2026-08-20, during the session).
    /// Same 14-field shape as the international channel, except that the
    /// open-interest slot carries traded volume.
    @Test("Sina's Shanghai spot payload reuses the international shape, with volume")
    func parseQuote() throws {
        let fixture = #"var hq_str_gds_AU9999="971.81,0,972.00,972.75,972.90,945.00,09:25:40,945.22,945.00,45418,8.00,100.00,2026-08-20,沪金99";"#
        let quote = try #require(
            SinaProvider.parseQuotes(text: fixture, mapping: ["gds_AU9999": gold]).first
        )

        #expect(quote.name == "沪金99")
        #expect(quote.price == 971.81)
        #expect(quote.previousClose == 945.22)
        #expect(quote.open == 945.00)
        #expect(quote.high == 972.90)
        #expect(quote.low == 945.00)
        #expect(quote.volume == 45_418)
        #expect(quote.currencyCode == "CNY")
        #expect(abs(quote.changePercent - 2.81) < 0.01)

        // The international channel puts open interest in that slot, so it must
        // not report a volume at all.
        let london = SymbolID(metal: .goldSpot)
        let londonQuote = try #require(SinaProvider.parseQuotes(
            text: #"var hq_str_hf_XAU="4490.41,4334.170,4490.41,4490.76,4499.23,4324.66,01:23:00,4334.17,4336.13,0,0,0,2026-08-20,伦敦金（现货黄金）";"#,
            mapping: ["hf_XAU": london]
        ).first)
        #expect(londonQuote.volume == nil)
    }

    /// The exchange's own file is ordered date, open, **close**, low, high —
    /// not the OHLC every other feed uses.
    @Test("The exchange's daily file decodes with close second")
    func parseOfficialDaily() throws {
        let data = Data(#"{"time":[["2026-08-18",953.0,955.16,948.5,961.0],["2026-08-19",952.0,945.22,939.5,959.99]]}"#.utf8)
        let candles = try ShanghaiGoldExchangeProvider.parseDailyCandles(data)

        #expect(candles.count == 2)
        let last = try #require(candles.last)
        #expect(last.open == 952.0)
        #expect(last.close == 945.22)
        #expect(last.low == 939.5)
        #expect(last.high == 959.99)
        #expect(last.high >= last.open && last.low <= last.close)
        // The endpoint publishes no volume; zero would read as "no trading".
        #expect(last.volume == nil)
    }

    /// Eastmoney also puts close second.
    @Test("Eastmoney rows decode with close second")
    func parseEastmoney() throws {
        let intraday = Data(#"{"data":{"klines":["2026-08-20 09:30,971.81,972.00,972.10,971.50,20"]}}"#.utf8)
        let bars = try EastmoneyProvider.parseCandles(intraday, intraday: true)
        #expect(bars.count == 1)
        #expect(bars[0].open == 971.81)
        #expect(bars[0].close == 972.00)
        #expect(bars[0].high == 972.10)
        #expect(bars[0].low == 971.50)
        #expect(bars[0].volume == 20)

        // A blocked Eastmoney request answers 200 with an empty body.
        #expect(try EastmoneyProvider.parseCandles(Data(#"{"data":null}"#.utf8), intraday: false).isEmpty)
    }

    @Test("Each source declares only the leg it actually serves")
    func routing() throws {
        let sina = SinaProvider().descriptor
        let exchange = ShanghaiGoldExchangeProvider().descriptor
        let eastmoney = EastmoneyProvider().descriptor

        // Quotes: Sina alone. Keeping the other two out of quote routing is what
        // stops Eastmoney from being polled — it bans an IP for hours after a burst.
        #expect(sina.supports(.quotes, in: .metalCN))
        #expect(!exchange.supports(.quotes, in: .metalCN))
        #expect(!eastmoney.supports(.quotes, in: .metalCN))

        // History: the exchange owns the daily series, Eastmoney the intraday one.
        #expect(exchange.supports(candles: .day, in: .metalCN))
        #expect(exchange.supports(candles: .week, in: .metalCN))
        #expect(!exchange.supports(candles: .minute5, in: .metalCN))
        #expect(eastmoney.supports(candles: .minute5, in: .metalCN))
        #expect(!eastmoney.supports(candles: .day, in: .metalCN))

        #expect(SinaProvider.sinaSymbol(for: gold) == "gds_AU9999")
        #expect(ShanghaiGoldExchangeProvider.instrumentID(for: .shanghaiGoldSpot) == "Au99.99")
        #expect(ShanghaiGoldExchangeProvider.instrumentID(for: .shanghaiGold) == nil)
        #expect(EastmoneyProvider.secid(for: .shanghaiGoldSpot) == "118.AU9999")
        #expect(EastmoneyProvider.secid(for: .gold) == nil)
    }

    @Test("Sina declines history for the contract it only quotes")
    func sinaHasNoSpotHistory() async throws {
        await #expect(throws: ProviderError.self) {
            _ = try await SinaProvider().candles(for: gold, period: .day, count: 5)
        }
    }
}
