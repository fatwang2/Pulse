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
}
#endif
