import Foundation
import Testing
@testable import PulseCore

@Suite("Symbol format conversion")
struct SymbolMappingTests {
    @Test("Normalization", arguments: [
        (Market.hk, "00700", "700"),
        (Market.hk, "700", "700"),
        (Market.us, "aapl", "AAPL"),
        (Market.sh, "600519", "600519"),
        (Market.sz, "000001", "000001"),
    ])
    func normalize(market: Market, input: String, expected: String) {
        #expect(SymbolID(market: market, code: input).code == expected)
    }

    @Test("Yahoo symbol mapping", arguments: [
        (SymbolID(market: .us, code: "AAPL"), "AAPL"),
        (SymbolID(market: .hk, code: "700"), "0700.HK"),
        (SymbolID(market: .hk, code: "9988"), "9988.HK"),
        (SymbolID(market: .sh, code: "600519"), "600519.SS"),
        (SymbolID(market: .sz, code: "000001"), "000001.SZ"),
    ])
    func yahooSymbol(id: SymbolID, expected: String) {
        #expect(YahooProvider.yahooSymbol(for: id) == expected)
    }

    @Test("Yahoo symbol reverse mapping", arguments: [
        ("0700.HK", SymbolID(market: .hk, code: "700")),
        ("600519.SS", SymbolID(market: .sh, code: "600519")),
        ("000001.SZ", SymbolID(market: .sz, code: "000001")),
        ("AAPL", SymbolID(market: .us, code: "AAPL")),
        ("^GSPC", SymbolID(market: .us, code: "^GSPC")),
    ])
    func yahooParse(raw: String, expected: SymbolID) {
        #expect(YahooProvider.symbolID(fromYahoo: raw) == expected)
    }

    @Test("Unsupported Yahoo symbols return nil")
    func yahooUnsupported() {
        #expect(YahooProvider.symbolID(fromYahoo: "7203.T") == nil)   // Tokyo
        #expect(YahooProvider.symbolID(fromYahoo: "USDCNY=X") == nil) // FX rate
        #expect(YahooProvider.symbolID(fromYahoo: "BTC-USD") == nil)  // Crypto belongs to Binance
        #expect(YahooProvider.symbolID(fromYahoo: "BRK-B") == SymbolID(market: .us, code: "BRK-B"))
        #expect(!YahooProvider().descriptor.markets.contains(.crypto))
    }

    @Test("Crypto pairs are structured internally and formatted per surface")
    func structuredCryptoPair() {
        let bitcoin = SymbolID(cryptoBase: "btc", quote: "usdt")

        #expect(bitcoin.market == .crypto)
        #expect(bitcoin.cryptoPair == CryptoPair(baseAsset: "BTC", quoteAsset: "USDT"))
        #expect(bitcoin.code == "BTC-USDT")
        #expect(bitcoin.displayCode == "BTC/USDT")
        #expect(bitcoin.currencyCode == "USDT")
        #expect(bitcoin.description == "BTC/USDT")
    }

    @Test("Legacy Yahoo crypto JSON migrates to structured USDT identity")
    func legacyCryptoPersistenceMigration() throws {
        let legacy = Data(#"{"market":"crypto","code":"BTC-USD"}"#.utf8)
        let decoded = try JSONDecoder().decode(SymbolID.self, from: legacy)
        let encoded = try JSONEncoder().encode(decoded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(decoded == SymbolID(cryptoBase: "BTC", quote: "USDT"))
        #expect(object["code"] == nil)
        let pair = try #require(object["cryptoPair"] as? [String: String])
        #expect(pair["baseAsset"] == "BTC")
        #expect(pair["quoteAsset"] == "USDT")
    }

    @Test("Tencent symbol mapping", arguments: [
        (SymbolID(market: .us, code: "AAPL"), "usAAPL"),
        (SymbolID(market: .hk, code: "700"), "hk00700"),
        (SymbolID(market: .sh, code: "600519"), "sh600519"),
        (SymbolID(market: .sz, code: "000001"), "sz000001"),
    ])
    func tencentSymbol(id: SymbolID, expected: String) {
        #expect(TencentProvider.tencentSymbol(for: id) == expected)
    }
}
