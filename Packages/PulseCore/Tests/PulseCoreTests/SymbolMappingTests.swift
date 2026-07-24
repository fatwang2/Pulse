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

    @Test("Index aliases collapse to provider-independent identities")
    func canonicalIndexIdentity() {
        let sp500 = SymbolID(index: .sp500)
        #expect(SymbolID(market: .us, code: "^GSPC") == sp500)
        #expect(SymbolID(market: .us, code: "^SPX") == sp500)
        #expect(SymbolID(market: .us, code: "INX") == sp500)
        #expect(sp500.market == .us)
        #expect(sp500.code == "SPX")
        #expect(sp500.indexID == .sp500)

        #expect(SymbolID(market: .us, code: "^IXIC").indexID == .nasdaqComposite)
        #expect(SymbolID(market: .us, code: "DJI").indexID == .dowJonesIndustrial)
        #expect(SymbolID(market: .hk, code: "^HSI").indexID == .hangSeng)
        #expect(SymbolID(market: .hk, code: "HSTECH").indexID == .hangSengTech)
        #expect(SymbolID(market: .sz, code: "399006").indexID == .chiNext)
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

    @Test("Yahoo maps canonical indices to Yahoo symbols")
    func yahooIndexSymbols() {
        #expect(YahooProvider.yahooSymbol(for: SymbolID(index: .sp500)) == "^GSPC")
        #expect(YahooProvider.yahooSymbol(for: SymbolID(index: .nasdaqComposite)) == "^IXIC")
        #expect(YahooProvider.yahooSymbol(for: SymbolID(index: .dowJonesIndustrial)) == "^DJI")
        #expect(YahooProvider.yahooSymbol(for: SymbolID(index: .russell1000)) == "^RUI")
        #expect(YahooProvider.yahooSymbol(for: SymbolID(index: .hangSeng)) == "^HSI")
        #expect(YahooProvider.yahooSymbol(for: SymbolID(index: .hangSengTech)) == "^HSTECH")
        #expect(YahooProvider.yahooSymbol(for: SymbolID(index: .chiNext)) == "399006.SZ")
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

    @Test("Yahoo index aliases decode to canonical identities")
    func yahooIndexParsing() {
        #expect(YahooProvider.symbolID(fromYahoo: "^GSPC") == SymbolID(index: .sp500))
        #expect(YahooProvider.symbolID(fromYahoo: "^IXIC") == SymbolID(index: .nasdaqComposite))
        #expect(YahooProvider.symbolID(fromYahoo: "^DJI") == SymbolID(index: .dowJonesIndustrial))
        #expect(YahooProvider.symbolID(fromYahoo: "^RUI") == SymbolID(index: .russell1000))
        #expect(YahooProvider.symbolID(fromYahoo: "^HSI") == SymbolID(index: .hangSeng))
        #expect(YahooProvider.symbolID(fromYahoo: "^HSTECH") == SymbolID(index: .hangSengTech))
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

    @Test("Legacy index JSON migrates without losing backward readability")
    func legacyIndexPersistenceMigration() throws {
        let legacy = Data(#"{"market":"us","code":"^GSPC"}"#.utf8)
        let decoded = try JSONDecoder().decode(SymbolID.self, from: legacy)
        let encoded = try JSONEncoder().encode(decoded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: String])

        #expect(decoded == SymbolID(index: .sp500))
        #expect(decoded.indexID == .sp500)
        #expect(object["indexID"] == "sp500")
        #expect(object["code"] == "^GSPC")
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

    @Test("Tencent maps canonical indices to Tencent symbols")
    func tencentIndexSymbols() {
        #expect(TencentProvider.tencentSymbol(for: SymbolID(index: .sp500)) == "usINX")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(index: .nasdaqComposite)) == "usIXIC")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(index: .dowJonesIndustrial)) == "usDJI")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(index: .nasdaq100)) == "usNDX")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(index: .vix)) == "usVIX")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(index: .russell1000)) == nil)
        #expect(TencentProvider.tencentSymbol(for: SymbolID(index: .hangSeng)) == "hkHSI")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(index: .hangSengTech)) == "hkHSTECH")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(index: .chiNext)) == "sz399006")
    }
}
