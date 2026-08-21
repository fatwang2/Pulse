import Foundation
import Testing
@testable import PulseCore

@Suite("Fuyao envelope and payload parsing")
struct FuyaoParserTests {
    /// Snapshot response shape from the official docs (fuyao.aicubes.cn/docs/api-reference/prices).
    static let snapshotFixture = Data("""
    {
      "code": 0,
      "message": "success",
      "request_id": "7e25804be878464ba420037155f041e6",
      "data": {
        "timestamp": 1784275991000,
        "total": 2,
        "item": [
          {
            "thscode": "600519.SH",
            "ticker": "600519",
            "volume": 3098875,
            "turnover": 3937375200,
            "last_price": 1277.8,
            "price_change": 21.8,
            "price_change_ratio_pct": 1.735669,
            "open_price": 1252.08,
            "high_price": 1282,
            "low_price": 1250.21,
            "prev_price": 1256
          },
          {
            "thscode": "000001.SZ",
            "ticker": "000001",
            "volume": null,
            "turnover": null,
            "last_price": 0,
            "price_change": null,
            "price_change_ratio_pct": null,
            "open_price": null,
            "high_price": null,
            "low_price": null,
            "prev_price": null
          }
        ]
      }
    }
    """.utf8)

    @Test("Parses a snapshot batch and drops priceless rows")
    func parseSnapshot() throws {
        let moutai = SymbolID(market: .sh, code: "600519")
        let pingan = SymbolID(market: .sz, code: "000001")
        let quotes = try FuyaoProvider.parseQuotes(
            data: Self.snapshotFixture,
            mapping: ["600519.SH": moutai, "000001.SZ": pingan]
        )
        #expect(quotes.count == 1)

        let quote = try #require(quotes.first)
        #expect(quote.symbol == moutai)
        #expect(quote.name == nil)  // snapshots carry no names; search/other sources do
        #expect(quote.price == 1277.8)
        #expect(quote.previousClose == 1256)
        #expect(quote.open == 1252.08)
        #expect(quote.high == 1282)
        #expect(quote.low == 1250.21)
        #expect(quote.volume == 3_098_875)
        #expect(quote.turnover == 3_937_375_200)
        #expect(quote.currencyCode == "CNY")
        #expect(quote.timestamp == Date(timeIntervalSince1970: 1_784_275_991))
    }

    @Test("Parses daily bars in ascending time order")
    func parseCandles() throws {
        let fixture = Data("""
        {
          "code": 0,
          "message": "success",
          "request_id": "b9f91af9c77a42d6b8a04738793d2fa2",
          "data": {
            "timestamp": 1747584000000,
            "item": [
              {
                "date_ms": 1716220800000,
                "open_price": 1602.0,
                "high_price": 1620.0,
                "low_price": 1598.0,
                "close_price": 1610.0,
                "volume": 2000000.0,
                "turnover": 3210000000.0
              },
              {
                "date_ms": 1716134400000,
                "open_price": 1611.602,
                "high_price": 1626.602,
                "low_price": 1601.722,
                "close_price": 1602.612,
                "volume": 3142572.0,
                "turnover": 5401389334.87
              }
            ]
          }
        }
        """.utf8)
        let candles = try FuyaoProvider.parseCandles(data: fixture)
        #expect(candles.count == 2)
        #expect(candles[0].time < candles[1].time)
        #expect(candles[0].open == 1611.602)
        #expect(candles[0].close == 1602.612)
        #expect(candles[1].close == 1610.0)
        #expect(candles[0].time == Date(timeIntervalSince1970: 1_716_134_400))
    }

    @Test("Parses ticker search and skips exchanges Pulse has no market for")
    func parseSearch() throws {
        let fixture = Data("""
        {
          "code": 0,
          "message": "success",
          "request_id": "c3d4e5f6",
          "data": {
            "timestamp": 1716105600000,
            "item": [
              {
                "thscode": "601318.SH",
                "ticker": "601318",
                "name": "中国平安",
                "exchange": "SH",
                "asset_type": "a-share",
                "currency": "CNY"
              },
              {
                "thscode": "510300.SH",
                "ticker": "510300",
                "name": "沪深300ETF",
                "exchange": "SH",
                "asset_type": "fund-etf",
                "currency": "CNY"
              },
              {
                "thscode": "832000.BJ",
                "ticker": "832000",
                "name": "北交所样例",
                "exchange": "BJ",
                "asset_type": "a-share",
                "currency": "CNY"
              }
            ]
          }
        }
        """.utf8)
        let results = try FuyaoProvider.parseSearch(data: fixture)
        #expect(results.count == 2)
        #expect(results[0].symbol == SymbolID(market: .sh, code: "601318"))
        #expect(results[0].name == "中国平安")
        #expect(results[0].type == .equity)
        #expect(results[1].symbol == SymbolID(market: .sh, code: "510300"))
        #expect(results[1].type == .etf)
    }

    @Test("Maps business error codes onto circuit-safe ProviderErrors")
    func errorMapping() {
        func error(code: Int) -> ProviderError {
            FuyaoProvider.providerError(code: code, message: "m", endpoint: "snapshot")
        }
        // Quota and upstream failures must trip the circuit so routing falls back.
        #expect(error(code: 4001).shouldTripCircuit)
        if case .rateLimited = error(code: 4001) {} else { Issue.record("4001 should map to rateLimited") }
        #expect(error(code: 5001).shouldTripCircuit)
        #expect(error(code: 5003).shouldTripCircuit)
        // Request-level problems must not take the source offline.
        #expect(!error(code: 1002).shouldTripCircuit)
        #expect(!error(code: 2001).shouldTripCircuit)
        #expect(!error(code: 2003).shouldTripCircuit)
        #expect(!error(code: 3001).shouldTripCircuit)
    }

    @Test("Business error inside an HTTP 200 body surfaces as a thrown ProviderError")
    func envelopeError() {
        let fixture = Data("""
        {"code":2003,"message":"Invalid or revoked API key","request_id":"d23e","data":null}
        """.utf8)
        #expect(throws: ProviderError.self) {
            _ = try FuyaoProvider.parseQuotes(data: fixture, mapping: [:])
        }
    }

    @Test("Maps only exchange-listed A-share identities to thscodes")
    func symbolMapping() {
        #expect(FuyaoProvider.thscode(for: SymbolID(market: .sh, code: "600519")) == "600519.SH")
        #expect(FuyaoProvider.thscode(for: SymbolID(market: .sz, code: "000001")) == "000001.SZ")
        #expect(FuyaoProvider.thscode(for: SymbolID(market: .hk, code: "700")) == nil)
        #expect(FuyaoProvider.thscode(for: SymbolID(market: .us, code: "AAPL")) == nil)
        // Indices ride semantic identities and the separate index endpoints.
        #expect(FuyaoProvider.thscode(for: SymbolID(index: .shanghaiComposite)) == nil)
        #expect(FuyaoProvider.thscode(for: SymbolID(metal: .goldSpot)) == nil)
    }
}
