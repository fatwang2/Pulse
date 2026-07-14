import Foundation
import Testing
@testable import PulseCore

/// Live checks against the real Longbridge quote gateway. Skipped unless a socket OTP is
/// supplied, so CI and normal test runs stay offline:
///   LONGBRIDGE_TEST_OTP=xxx swift test --filter LongbridgeGatewayIntegrationTests
@Suite("Longbridge gateway integration", .serialized)
struct LongbridgeGatewayIntegrationTests {
    static var otp: String? { ProcessInfo.processInfo.environment["LONGBRIDGE_TEST_OTP"] }

    @Test(.enabled(if: otp != nil))
    func authenticatesAndPullsQuoteAndCandles() async throws {
        let otp = try #require(Self.otp)
        let socket = LongbridgeSocket()
        // Inject the externally-acquired OTP directly, bypassing the HTTP exchange.
        await socket.updateOTPSource { otp }

        // Quote pull (cmd 11)
        let quoteBody = LongbridgeMessages.multiSecurityRequest(symbols: ["700.HK"])
        let quoteResponse = try await socket.request(.querySecurityQuote, body: quoteBody)
        let quotes = try LongbridgeMessages.decodeSecurityQuoteResponse(quoteResponse)
        #expect(quotes.count == 1)
        let quote = try #require(quotes.first)
        #expect(quote.symbol == "700.HK")
        let price = try #require(quote.lastDone)
        #expect(price > 0)
        print("[integration] 700.HK last_done=\(price) prev_close=\(quote.prevClose ?? 0) ts=\(quote.timestamp)")

        // Candlestick pull (cmd 19) over the same authenticated connection
        let candleBody = LongbridgeMessages.candlestickRequest(symbol: "700.HK", period: .minute5, count: 10)
        let candleResponse = try await socket.request(.queryCandlestick, body: candleBody)
        let candles = try LongbridgeMessages.decodeCandlestickResponse(candleResponse)
        #expect(!candles.isEmpty)
        #expect(candles.count <= 10)
        let last = try #require(candles.last)
        #expect(last.close > 0)
        #expect(last.time.timeIntervalSinceNow > -24 * 3600)
        print("[integration] candles=\(candles.count) last close=\(last.close) at \(last.time)")
    }
}
