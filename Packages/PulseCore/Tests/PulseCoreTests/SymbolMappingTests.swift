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
        #expect(YahooProvider.symbolID(fromYahoo: "^N225") == SymbolID(index: .nikkei225))
        #expect(YahooProvider.symbolID(fromYahoo: "^KS11") == SymbolID(index: .kospi))
    }

    /// Both Korea Exchange boards are addressed by suffix, and the code alone
    /// does not say which: 035720 is KOSPI, so `.KQ` would price a different
    /// instrument entirely.
    @Test("Tokyo and Seoul symbols round-trip through their board suffixes")
    func japanKoreaSymbolRoundTrip() {
        let toyota = SymbolID(market: .jp, code: "7203")
        let samsung = SymbolID(market: .kr, code: "005930")
        let ecopro = SymbolID(market: .kq, code: "247540")

        #expect(YahooProvider.yahooSymbol(for: toyota) == "7203.T")
        #expect(YahooProvider.yahooSymbol(for: samsung) == "005930.KS")
        #expect(YahooProvider.yahooSymbol(for: ecopro) == "247540.KQ")

        #expect(YahooProvider.symbolID(fromYahoo: "7203.T") == toyota)
        #expect(YahooProvider.symbolID(fromYahoo: "005930.KS") == samsung)
        #expect(YahooProvider.symbolID(fromYahoo: "247540.KQ") == ecopro)

        // A Korean code is six digits whose leading zeros carry meaning.
        #expect(samsung.code == "005930")
        #expect(samsung.description == "005930.KS")
        #expect(ecopro.description == "247540.KQ")
        #expect(toyota.description == "7203.T")
        #expect(samsung.currencyCode == "KRW")
        #expect(toyota.currencyCode == "JPY")
    }

    @Test("Unsupported Yahoo symbols return nil")
    func yahooUnsupported() {
        #expect(YahooProvider.symbolID(fromYahoo: "USDCNY=X") == nil) // FX rate
        #expect(YahooProvider.symbolID(fromYahoo: "7203.TO") == nil)  // Toronto, not Tokyo
        #expect(YahooProvider.symbolID(fromYahoo: "TSLA.MX") == nil)  // Mexico
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

    @Test("Metal codes collapse to provider-independent identities")
    func canonicalMetalIdentity() {
        let gold = SymbolID(metal: .gold)
        #expect(SymbolID(market: .metal, code: "GC") == gold)
        #expect(SymbolID(market: .metal, code: "hf_GC") == gold)
        #expect(SymbolID(market: .metal, code: "gc=f") == gold)
        // Yahoo's futures notation is the one US shape that becomes a metal.
        #expect(SymbolID(market: .us, code: "GC=F") == gold)
        #expect(gold.market == .metal)
        #expect(gold.code == "GC")
        #expect(gold.metalID == .gold)
        #expect(gold.currencyCode == "USD")
        #expect(!gold.isDescribable)

        #expect(SymbolID(market: .metal, code: "SI").metalID == .silver)
        #expect(SymbolID(market: .metal, code: "PL").metalID == .platinum)
        #expect(SymbolID(market: .metal, code: "PA").metalID == .palladium)
        // Tencent names the platinum-group futures XPT / XPD; both providers'
        // codes for a modeled contract resolve to it.
        #expect(SymbolID(market: .metal, code: "hf_XPT") == SymbolID(metal: .platinum))
        #expect(SymbolID(market: .metal, code: "XPD") == SymbolID(metal: .palladium))

        // Spot is its own identity, not the futures contract under another code.
        #expect(SymbolID(market: .metal, code: "XAU") == SymbolID(metal: .goldSpot))
        #expect(SymbolID(market: .metal, code: "hf_XAG") == SymbolID(metal: .silverSpot))
        #expect(SymbolID(metal: .goldSpot).displayCode == "XAU")
        #expect(SymbolID(metal: .goldSpot) != SymbolID(metal: .gold))

        // Shanghai's spot contract is a different instrument from its futures,
        // the same way London spot differs from COMEX.
        #expect(SymbolID(market: .metalCN, code: "AU9999") == SymbolID(metal: .shanghaiGoldSpot))
        #expect(SymbolID(market: .metalCN, code: "Au99.99") == SymbolID(metal: .shanghaiGoldSpot))
        #expect(SymbolID(metal: .shanghaiGoldSpot) != SymbolID(metal: .shanghaiGold))
        #expect(SymbolID(metal: .shanghaiGoldSpot).currencyCode == "CNY")
        #expect(PreciousMetalID.shanghaiGoldSpot.isSpot)
        #expect(!PreciousMetalID.shanghaiGold.isSpot)

        // A metal identity carries its own market, which is what makes Shanghai
        // price in CNY on a Chinese session while COMEX stays USD.
        let shanghai = SymbolID(metal: .shanghaiGold)
        #expect(shanghai.market == .metalCN)
        #expect(shanghai.currencyCode == "CNY")
        #expect(SymbolID(market: .metal, code: "AU0") == shanghai)
        #expect(SymbolID(market: .metalCN, code: "AU0") == shanghai)
        #expect(SymbolID(metal: .gold).currencyCode == "USD")
    }

    @Test("A listed equity is never mistaken for a metal")
    func metalResolutionStaysExact() {
        #expect(SymbolID(market: .us, code: "GOLD").metalID == nil)
        #expect(SymbolID(market: .us, code: "GC").metalID == nil)
        #expect(SymbolID(market: .us, code: "PA").metalID == nil)
        // A spot code names the spot instrument, never the futures contract.
        #expect(SymbolID(market: .metal, code: "XAU").metalID == .goldSpot)
    }

    @Test("Metal JSON stays readable to the preceding app version")
    func metalPersistenceCompatibility() throws {
        let encoded = try JSONEncoder().encode(SymbolID(metal: .silver))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: String])

        // An unknown market value would fail the whole snapshot on an older build.
        #expect(object["market"] == "us")
        #expect(object["code"] == "SI=F")
        #expect(object["metalID"] == "silver")

        let decoded = try JSONDecoder().decode(SymbolID.self, from: encoded)
        #expect(decoded == SymbolID(metal: .silver))
        #expect(decoded.market == .metal)
    }

    @Test("Metal search accepts names, tickers, spot codes, and pinyin")
    func metalCatalogSearch() {
        // "黄金" names three instruments, and spot leads: that is what the word
        // means to someone asking for the price of gold.
        #expect(PreciousMetalCatalog.matches("黄金")
            == [.goldSpot, .gold, .shanghaiGoldSpot, .shanghaiGold])
        #expect(PreciousMetalCatalog.matches("gold")
            == [.goldSpot, .gold, .shanghaiGoldSpot, .shanghaiGold])
        #expect(PreciousMetalCatalog.matches("白银") == [.silverSpot, .silver, .shanghaiSilver])
        #expect(PreciousMetalCatalog.matches("huangjin") == [.goldSpot, .gold])
        #expect(PreciousMetalCatalog.matches("silver") == [.silverSpot, .silver, .shanghaiSilver])
        #expect(PreciousMetalCatalog.matches("铂金") == [.platinum])
        #expect(PreciousMetalCatalog.matches("パラジウム") == [.palladium])
        // One CJK character is a word; one latin letter is noise.
        #expect(PreciousMetalCatalog.matches("金").count == 6)
        #expect(PreciousMetalCatalog.matches("g").isEmpty)
        #expect(PreciousMetalCatalog.matches("AAPL").isEmpty)

        // The category is a search term of its own.
        #expect(PreciousMetalCatalog.matches("贵金属") == PreciousMetalID.allCases)
        #expect(PreciousMetalCatalog.matches("貴金属") == PreciousMetalID.allCases)
        #expect(PreciousMetalCatalog.matches("metals") == PreciousMetalID.allCases)

        // Naming a contract picks exactly one of the two instruments.
        #expect(PreciousMetalCatalog.matches("黄金期货") == [.gold])
        #expect(PreciousMetalCatalog.matches("纽约黄金") == [.gold])
        #expect(PreciousMetalCatalog.matches("COMEX黄金") == [.gold])
        #expect(PreciousMetalCatalog.matches("gold futures") == [.gold])
        #expect(PreciousMetalCatalog.matches("现货黄金") == [.goldSpot])
        #expect(PreciousMetalCatalog.matches("伦敦金") == [.goldSpot])
        #expect(PreciousMetalCatalog.matches("spot gold") == [.goldSpot])
        #expect(PreciousMetalCatalog.matches("XAU") == [.goldSpot])
        #expect(PreciousMetalCatalog.matches("伦敦银") == [.silverSpot])
        // A named contract that does not exist here still answers with the metal.
        #expect(PreciousMetalCatalog.matches("伦敦铂金") == [.platinum])

        // A venue is more specific than a kind, and inside Shanghai the spot
        // contract leads: "上海黄金" is Au99.99 to almost everyone who says it.
        #expect(PreciousMetalCatalog.matches("上海黄金") == [.shanghaiGoldSpot, .shanghaiGold])
        #expect(PreciousMetalCatalog.matches("上海金") == [.shanghaiGoldSpot, .shanghaiGold])
        #expect(PreciousMetalCatalog.matches("沪金") == [.shanghaiGoldSpot, .shanghaiGold])
        #expect(PreciousMetalCatalog.matches("shanghai gold") == [.shanghaiGoldSpot, .shanghaiGold])
        #expect(PreciousMetalCatalog.matches("沪银") == [.shanghaiSilver])
        // Exact codes still name exactly one.
        #expect(PreciousMetalCatalog.matches("AU9999") == [.shanghaiGoldSpot])
        #expect(PreciousMetalCatalog.matches("AU0") == [.shanghaiGold])
        // Shanghai equity indices are not metals.
        #expect(PreciousMetalCatalog.matches("沪深300").isEmpty)
        #expect(PreciousMetalCatalog.matches("山东黄金").isEmpty)
        #expect(PreciousMetalCatalog.matches("紫金矿业").isEmpty)
        #expect(PreciousMetalCatalog.matches("goldman").isEmpty)
        // Gold ETFs are their own instruments, and the providers already find them.
        #expect(PreciousMetalCatalog.matches("黄金ETF").isEmpty)

        // A symbol pasted from a provider or a chart URL still lands.
        #expect(PreciousMetalCatalog.matches("GC=F") == [.gold])
        #expect(PreciousMetalCatalog.matches("hf_XPD") == [.palladium])

        let results = PreciousMetalCatalog.search("gold")
        #expect(results.first?.symbol == SymbolID(metal: .goldSpot))
        #expect(results.first?.type == .commodity)
        #expect(results.first?.exchangeName == "London")
    }

    @Test("Metal wire symbols per provider")
    func metalProviderSymbols() {
        #expect(TencentProvider.tencentSymbol(for: SymbolID(metal: .gold)) == "hf_GC")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(metal: .silver)) == "hf_SI")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(metal: .platinum)) == "hf_XPT")
        #expect(TencentProvider.tencentSymbol(for: SymbolID(metal: .palladium)) == "hf_XPD")

        #expect(YahooProvider.yahooSymbol(for: SymbolID(metal: .gold)) == "GC=F")
        #expect(YahooProvider.yahooSymbol(for: SymbolID(metal: .silver)) == "SI=F")
        #expect(YahooProvider.yahooSymbol(for: SymbolID(metal: .platinum)) == "PL=F")
        #expect(YahooProvider.yahooSymbol(for: SymbolID(metal: .palladium)) == "PA=F")
        // Yahoo has no spot symbol at all, so it declines rather than guessing.
        #expect(SymbolID(metal: .goldSpot).metalID?.isSpot == true)
        #expect(SymbolID(metal: .gold).metalID?.isSpot == false)

        #expect(YahooProvider.symbolID(fromYahoo: "GC=F") == SymbolID(metal: .gold))
        #expect(YahooProvider.symbolID(fromYahoo: "pa=f") == SymbolID(metal: .palladium))
        // Neither micro contracts nor other commodities are modeled.
        #expect(YahooProvider.symbolID(fromYahoo: "MGC=F") == nil)
        #expect(YahooProvider.symbolID(fromYahoo: "CL=F") == nil)

        // A metal-market code Pulse does not model (rhodium here) must not borrow
        // a contract it was never asked for.
        let unmodelled = SymbolID(market: .metal, code: "RH")
        #expect(unmodelled.metalID == nil)
        #expect(TencentProvider.tencentSymbol(for: unmodelled) == nil)
        #expect(YahooProvider.yahooSymbol(for: unmodelled) == "RH")
    }

    @Test("Metal quotes route to Tencent, history to Yahoo")
    func metalCoverage() {
        let tencent = TencentProvider().descriptor
        let yahoo = YahooProvider().descriptor

        #expect(tencent.supports(.quotes, in: .metal))
        #expect(tencent.delay[.metal] == 0)
        #expect(!tencent.supports(.candles, in: .metal))
        #expect(yahoo.supports(.quotes, in: .metal))
        #expect(yahoo.supports(candles: .day, in: .metal))
        #expect(yahoo.supports(candles: .minute5, in: .metal))
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
