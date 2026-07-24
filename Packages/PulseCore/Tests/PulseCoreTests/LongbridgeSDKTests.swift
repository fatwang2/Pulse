#if os(macOS)
import Testing
@testable import PulseCore

@Suite("Longbridge official SDK")
struct LongbridgeSDKTests {
    @Test func mapsSymbolsToLongbridgeFormat() {
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .hk, code: "700")) == "700.HK")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .hk, code: "HSTECH")) == "HSTECH.HK")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .us, code: "AAPL")) == "AAPL.US")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .us, code: "COLO")) == "COLO.US")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .us, code: "IXIC")) == ".IXIC.US")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .us, code: "DJI")) == ".DJI.US")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .us, code: "^SPX")) == ".SPX.US")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .us, code: "^GSPC")) == ".SPX.US")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .us, code: "^VIX")) == ".VIX.US")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(index: .russell1000)) == nil)
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(index: .russell2000)) == nil)
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(index: .hangSeng)) == "HSI.HK")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(index: .shanghaiComposite)) == "000001.SH")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(index: .shenzhenComponent)) == "399001.SZ")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .sh, code: "603986")) == "603986.SH")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .sz, code: "300750")) == "300750.SZ")
        #expect(LongbridgeProvider.longbridgeSymbol(
            for: SymbolID(cryptoBase: "BTC", quote: "USDT")) == nil)
    }

    @Test func invalidSymbolIsARequestError() {
        let error = LongbridgeSDKErrorClassifier.providerError(
            code: 301_600,
            message: "invalid symbol"
        )

        guard case .clientError(let status, _) = error else {
            Issue.record("Expected a request-level client error, got \(error)")
            return
        }
        #expect(status == 400)
        #expect(!error.shouldTripCircuit)
        #expect(LongbridgeSDKErrorClassifier.isInvalidSymbol(error))
    }
}
#endif
