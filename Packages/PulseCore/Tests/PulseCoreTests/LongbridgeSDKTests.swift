#if os(macOS)
import Foundation
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

    @Test("Auth-sounding transport failures classify as network, not authentication")
    func transportWordingBeatsAuthWording() {
        let error = LongbridgeSDKErrorClassifier.providerError(
            code: 0,
            message: "authentication handshake timed out: connect to openapi-quote failed"
        )
        guard case .network = error else {
            Issue.record("Expected a network error, got \(error)")
            return
        }
    }

    @Test("Longbridge 401xxx gateway codes classify as authentication")
    func gatewayAuthCodesAreAuthentication() {
        let error = LongbridgeSDKErrorClassifier.providerError(
            code: 401_102,
            message: "the access token has been revoked"
        )
        guard case .clientError(let status, let detail) = error else {
            Issue.record("Expected an authentication client error, got \(error)")
            return
        }
        #expect(status == 401_102)
        #expect(detail == "the access token has been revoked")
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

    @Test("Runtime quote package metadata prefers real-time over Basic")
    func realtimePackageWinsBasicPackage() {
        let packages = [
            LongbridgeQuotePackage(
                key: "HK_Basic",
                name: "延迟 15 分钟行情",
                description: "行情数据延迟 15 分钟"
            ),
            LongbridgeQuotePackage(
                key: "HK_L1_OpenAPI",
                name: "LV1 实时行情（OpenAPI）",
                description: "实时成交行情"
            ),
        ]

        #expect(
            LongbridgeQuoteFreshness.packageDelay(
                for: SymbolID(market: .hk, code: "700"),
                packages: packages
            ) == 0
        )
    }

    @Test("Basic package declares a 15-minute delay")
    func basicPackageDeclaresDelay() {
        let packages = [
            LongbridgeQuotePackage(
                key: "HK_Basic",
                name: "Delayed quotes",
                description: "15 min delay"
            )
        ]

        #expect(
            LongbridgeQuoteFreshness.packageDelay(
                for: SymbolID(market: .hk, code: "700"),
                packages: packages
            )
                == LongbridgeQuoteFreshness.delayedQuoteInterval
        )
    }

    @Test("Market access is derived from the negotiated package list")
    func derivesMarketAccess() {
        let packages = [
            LongbridgeQuotePackage(
                key: "HK_Basic",
                name: "Delayed quotes",
                description: "15 min delay"
            ),
            LongbridgeQuotePackage(
                key: "CN_Connect",
                name: "China Connect",
                description: "Real-time"
            ),
            LongbridgeQuotePackage(
                key: "US_QBBO_OpenAPI",
                name: "US QBBO",
                description: "OpenAPI real-time"
            ),
        ]

        #expect(LongbridgeProvider.quoteAccess(for: .hk, packages: packages) == .delayed)
        #expect(LongbridgeProvider.quoteAccess(for: .sh, packages: packages) == .realtime)
        #expect(LongbridgeProvider.quoteAccess(for: .sz, packages: packages) == .realtime)
        #expect(LongbridgeProvider.quoteAccess(for: .us, packages: packages) == .realtime)
    }

    @Test("Index-only access does not mark the whole market real-time")
    func indexOnlyAccessDoesNotUpgradeMarket() {
        let packages = [
            LongbridgeQuotePackage(
                key: "HK_Basic",
                name: "Delayed quotes",
                description: "15 min delay"
            ),
            LongbridgeQuotePackage(
                key: "HK_HangSengIndex_AllTerminals",
                name: "Hang Seng Index",
                description: "Real-time index quotes"
            ),
        ]

        #expect(LongbridgeProvider.quoteAccess(for: .hk, packages: packages) == .delayed)
    }

    @Test("A real-time index package does not upgrade an equity quote")
    func indexPackageDoesNotUpgradeEquity() {
        let packages = [
            LongbridgeQuotePackage(
                key: "HK_Basic",
                name: "延迟 15 分钟行情",
                description: "行情数据延迟 15 分钟"
            ),
            LongbridgeQuotePackage(
                key: "HK_HangSengIndex_AllTerminals",
                name: "恒生指数实时行情",
                description: "恒生指数实时行情"
            ),
        ]

        #expect(
            LongbridgeQuoteFreshness.packageDelay(
                for: SymbolID(market: .hk, code: "700"),
                packages: packages
            ) == LongbridgeQuoteFreshness.delayedQuoteInterval
        )
        #expect(
            LongbridgeQuoteFreshness.packageDelay(
                for: SymbolID(index: .hangSeng),
                packages: packages
            ) == 0
        )
    }

    @Test("A broad delayed market package also covers indices")
    func broadPackageCoversIndex() {
        let packages = [
            LongbridgeQuotePackage(
                key: "CN_Basic",
                name: "15-min Delay",
                description: "A-shares 15-min delayed quotes"
            ),
        ]

        #expect(
            LongbridgeQuoteFreshness.packageDelay(
                for: SymbolID(index: .shanghaiComposite),
                packages: packages
            ) == LongbridgeQuoteFreshness.delayedQuoteInterval
        )
    }

    @Test("System region never changes the default endpoint")
    func systemRegionDoesNotChangeEndpoint() {
        #expect(
            !LongbridgeEndpointSelection.usesChinaEndpoint(
                environment: [:],
                timeZoneIdentifier: "Asia/Shanghai",
                localeRegion: "US"
            )
        )
        #expect(
            !LongbridgeEndpointSelection.usesChinaEndpoint(
                environment: [:],
                timeZoneIdentifier: "America/Los_Angeles",
                localeRegion: "CN"
            )
        )
    }

    @Test("Explicit region override wins over system settings")
    func explicitRegionOverrideWins() {
        #expect(
            !LongbridgeEndpointSelection.usesChinaEndpoint(
                environment: ["LONGBRIDGE_REGION": "GLOBAL"],
                timeZoneIdentifier: "Asia/Shanghai",
                localeRegion: "CN"
            )
        )
        #expect(
            LongbridgeEndpointSelection.usesChinaEndpoint(
                environment: ["LONGPORT_REGION": "cn"],
                timeZoneIdentifier: "America/Los_Angeles",
                localeRegion: "US"
            )
        )
    }

    @Test("Empty pre-market uses the latest valid overnight trade")
    func emptyPreMarketUsesOvernightTrade() throws {
        let regularAt = try #require(Self.marketDate(
            year: 2026, month: 7, day: 31, hour: 16, minute: 0, market: .us
        ))
        let postAt = try #require(Self.marketDate(
            year: 2026, month: 7, day: 31, hour: 19, minute: 59, market: .us
        ))
        let overnightAt = try #require(Self.marketDate(
            year: 2026, month: 8, day: 3, hour: 3, minute: 59, market: .us
        ))
        let preMarketAt = try #require(Self.marketDate(
            year: 2026, month: 8, day: 3, hour: 4, minute: 0, market: .us
        ))
        let receivedAt = try #require(Self.marketDate(
            year: 2026, month: 8, day: 3, hour: 5, minute: 44, market: .us
        ))
        let snapshot = LBSDKSecurityQuote(
            symbol: "CRAK.US",
            lastDone: 55.24,
            previousClose: 55.82,
            open: 55.79,
            high: 55.79,
            low: 54.77,
            timestamp: Self.timestamp(regularAt),
            volume: 324_808,
            turnover: 17_882_060,
            preMarket: Self.extendedQuote(
                price: 0,
                previousClose: 55.24,
                at: preMarketAt
            ),
            postMarket: Self.extendedQuote(
                price: 55.30,
                previousClose: 55.24,
                at: postAt
            ),
            overnight: Self.extendedQuote(
                price: 55.41,
                previousClose: 55.24,
                at: overnightAt
            )
        )

        let quote = try #require(LongbridgeSDKBridge.quote(
            from: snapshot,
            symbol: SymbolID(market: .us, code: "CRAK"),
            packages: [],
            receivedAt: receivedAt
        ))

        #expect(quote.marketState == .preMarket)
        #expect(quote.price == 55.41)
        #expect(quote.previousClose == 55.24)
        #expect(abs(quote.change - 0.17) < 0.000_001)
        #expect(quote.timestamp == overnightAt)
        #expect(quote.regularSession?.price == 55.24)
        #expect(quote.regularSession?.previousClose == 55.82)
    }

    @Test("Empty extended sessions fall back to regular without losing the clock session")
    func emptyExtendedSessionsUseRegularTrade() throws {
        let regularAt = try #require(Self.marketDate(
            year: 2026, month: 7, day: 31, hour: 16, minute: 0, market: .us
        ))
        let preMarketAt = try #require(Self.marketDate(
            year: 2026, month: 8, day: 3, hour: 4, minute: 0, market: .us
        ))
        let receivedAt = try #require(Self.marketDate(
            year: 2026, month: 8, day: 3, hour: 5, minute: 44, market: .us
        ))
        let snapshot = LBSDKSecurityQuote(
            symbol: "CRAK.US",
            lastDone: 55.24,
            previousClose: 55.82,
            open: 0,
            high: 0,
            low: 0,
            timestamp: Self.timestamp(regularAt),
            volume: 324_808,
            turnover: 17_882_060,
            preMarket: Self.extendedQuote(
                price: 0,
                previousClose: 55.24,
                at: preMarketAt
            ),
            postMarket: nil,
            overnight: nil
        )

        let quote = try #require(LongbridgeSDKBridge.quote(
            from: snapshot,
            symbol: SymbolID(market: .us, code: "CRAK"),
            packages: [],
            receivedAt: receivedAt
        ))

        #expect(quote.marketState == .preMarket)
        #expect(quote.price == 55.24)
        #expect(quote.previousClose == 55.82)
        #expect(quote.timestamp == regularAt)
        #expect(quote.regularSession == nil)
        #expect(quote.open == nil)
        #expect(quote.high == nil)
        #expect(quote.low == nil)
    }

    @Test("An empty-session push preserves the last valid price and trade time")
    func emptySessionPushPreservesLastTrade() throws {
        let overnightAt = try #require(Self.marketDate(
            year: 2026, month: 8, day: 3, hour: 3, minute: 59, market: .us
        ))
        let preMarketAt = try #require(Self.marketDate(
            year: 2026, month: 8, day: 3, hour: 4, minute: 0, market: .us
        ))
        let receivedAt = try #require(Self.marketDate(
            year: 2026, month: 8, day: 3, hour: 4, minute: 1, market: .us
        ))
        let base = Quote(
            symbol: SymbolID(market: .us, code: "CRAK"),
            price: 55.41,
            previousClose: 55.24,
            open: 55.20,
            high: 55.50,
            low: 55.10,
            volume: 1_000,
            timestamp: overnightAt,
            marketState: .overnight,
            regularSession: .init(price: 55.24, previousClose: 55.82)
        )
        let push = LBSDKPushQuote(
            symbol: "CRAK.US",
            lastDone: 0,
            open: 0,
            high: 0,
            low: 0,
            timestamp: Self.timestamp(preMarketAt),
            volume: 0,
            turnover: 0,
            tradeSession: 1
        )

        let quote = LongbridgeSDKBridge.applying(
            push,
            to: base,
            packages: [],
            receivedAt: receivedAt
        )

        #expect(quote.marketState == .preMarket)
        #expect(quote.price == 55.41)
        #expect(quote.timestamp == overnightAt)
        #expect(quote.open == 55.20)
        #expect(quote.high == 55.50)
        #expect(quote.low == 55.10)
        #expect(quote.regularSession == base.regularSession)
    }

    @Test("A pre-market push preserves the previous regular-session stats")
    func preMarketPushPreservesRegularStats() throws {
        let regularAt = try #require(Self.marketDate(
            year: 2026, month: 7, day: 31, hour: 16, minute: 0, market: .us
        ))
        let preMarketAt = try #require(Self.marketDate(
            year: 2026, month: 8, day: 3, hour: 7, minute: 56, market: .us
        ))
        let base = Quote(
            symbol: SymbolID(market: .us, code: "CRAK"),
            price: 55.24,
            previousClose: 55.82,
            open: 55.79,
            high: 55.79,
            low: 54.77,
            volume: 324_808,
            turnover: 17_882_060,
            timestamp: regularAt,
            marketState: .preMarket
        )
        let push = LBSDKPushQuote(
            symbol: "CRAK.US",
            lastDone: 54.80,
            open: 54.41,
            high: 54.80,
            low: 53.32,
            timestamp: Self.timestamp(preMarketAt),
            volume: 1_110,
            turnover: 59_308.79,
            tradeSession: 1
        )

        let quote = LongbridgeSDKBridge.applying(
            push,
            to: base,
            packages: [],
            receivedAt: preMarketAt
        )

        #expect(quote.marketState == .preMarket)
        #expect(quote.price == 54.80)
        #expect(quote.previousClose == 55.24)
        #expect(quote.timestamp == preMarketAt)
        #expect(quote.open == 55.79)
        #expect(quote.high == 55.79)
        #expect(quote.low == 54.77)
        #expect(quote.volume == 324_808)
        #expect(quote.turnover == 17_882_060)
        #expect(quote.regularSession?.price == 55.24)
        #expect(quote.regularSession?.previousClose == 55.82)
    }

    @Test("A near-exact market timestamp lag detects delayed data")
    func timestampDetectsDelayedData() throws {
        let receivedAt = try #require(Self.marketDate(
            year: 2026,
            month: 7,
            day: 27,
            hour: 13,
            minute: 30,
            market: .hk
        ))
        let timestamp = receivedAt.addingTimeInterval(-15 * 60)

        #expect(
            LongbridgeQuoteFreshness.effectiveDelay(
                for: SymbolID(market: .hk, code: "700"),
                timestamp: timestamp,
                packages: [],
                receivedAt: receivedAt
            ) == LongbridgeQuoteFreshness.delayedQuoteInterval
        )
    }

    @Test("Static source annotation preserves negotiated delay")
    func sourcedQuotePreservesNegotiatedDelay() {
        let symbol = SymbolID(market: .hk, code: "700")
        let quote = Quote(
            symbol: symbol,
            price: 400,
            previousClose: 390,
            sourceDelay: 15 * 60
        )
        let descriptor = ProviderDescriptor(
            id: LongbridgeProvider.providerID,
            name: "Longbridge",
            markets: [.hk],
            capabilities: [.quotes],
            delay: [.hk: 0]
        )

        #expect(
            quote.sourced(by: descriptor).sourceDelay
                == LongbridgeQuoteFreshness.delayedQuoteInterval
        )
    }

    private static func marketDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        market: Market
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))
    }

    private static func timestamp(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970)
    }

    private static func extendedQuote(
        price: Double,
        previousClose: Double,
        at date: Date
    ) -> LBSDKPrePostQuote {
        LBSDKPrePostQuote(
            lastDone: price,
            timestamp: timestamp(date),
            volume: 0,
            turnover: 0,
            high: price,
            low: price,
            previousClose: previousClose
        )
    }
}
#endif
