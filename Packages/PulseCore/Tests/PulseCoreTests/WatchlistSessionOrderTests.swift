import Foundation
import Testing
@testable import PulseCore

@Suite("Market schedule window")
struct MarketScheduleWindowTests {
    private func beijing(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? .distantPast
    }

    @Test("Asia day covers 08:00..<17:00 Beijing")
    func asiaDayBounds() {
        // 08:00 and 16:59 Beijing
        #expect(MarketScheduleWindow.at(beijing("2025-06-16T00:00:00Z")) == .asiaDay)
        #expect(MarketScheduleWindow.at(beijing("2025-06-16T08:59:00Z")) == .asiaDay)
    }

    @Test("US evening covers 17:00..<08:00 Beijing")
    func usEveningBounds() {
        // 17:00 Beijing and 07:59 Beijing
        #expect(MarketScheduleWindow.at(beijing("2025-06-16T09:00:00Z")) == .usEvening)
        #expect(MarketScheduleWindow.at(beijing("2025-06-16T23:59:00Z")) == .usEvening)
    }
}

@Suite("Watchlist session order")
struct WatchlistSessionOrderTests {
    private let aapl = SymbolID(market: .us, code: "AAPL")
    private let tsla = SymbolID(market: .us, code: "TSLA")
    private let tencent = SymbolID(market: .hk, code: "00700")
    private let maotai = SymbolID(market: .sh, code: "600519")
    private let pingAn = SymbolID(market: .sz, code: "000001")
    private let btc = SymbolID(market: .crypto, code: "BTC-USDT")

    private func beijing(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? .distantPast
    }

    @Test("Asia day uses HK → China A → US → crypto")
    func asiaDayOrder() {
        let base = [aapl, maotai, tencent, pingAn, tsla, btc]
        let ordered = WatchlistSessionOrder.orderedSymbols(
            base,
            at: beijing("2025-06-16T02:00:00Z") // 10:00 Beijing
        )
        #expect(ordered == [tencent, maotai, pingAn, aapl, tsla, btc])
    }

    @Test("US evening uses US → HK → China A → crypto")
    func usEveningOrder() {
        let base = [aapl, maotai, tencent, pingAn, tsla, btc]
        let ordered = WatchlistSessionOrder.orderedSymbols(
            base,
            at: beijing("2025-06-16T10:00:00Z") // 18:00 Beijing
        )
        #expect(ordered == [aapl, tsla, tencent, maotai, pingAn, btc])
    }

    @Test("Pins stay inside their market block")
    func pinsWithinBlock() {
        let base = [aapl, maotai, tencent, pingAn, tsla]
        let ordered = WatchlistSessionOrder.orderedSymbols(
            base,
            pinned: [tsla, pingAn],
            at: beijing("2025-06-16T02:00:00Z") // asia day
        )
        // HK → China A (pingAn pinned, then maotai) → US (tsla pinned, then aapl)
        #expect(ordered == [tencent, pingAn, maotai, tsla, aapl])
    }

    @Test("Relative order inside a market is preserved from the base sequence")
    func preservesRelativeOrder() {
        let base = [tsla, aapl, pingAn, maotai]
        let ordered = WatchlistSessionOrder.orderedSymbols(
            base,
            at: beijing("2025-06-16T02:00:00Z")
        )
        #expect(ordered == [pingAn, maotai, tsla, aapl])
    }

    @Test("A-share close does not reshuffle while still in asia day")
    func noReshuffleAfterAShareClose() {
        let base = [maotai, tencent, aapl]
        let morning = WatchlistSessionOrder.orderedSymbols(
            base,
            at: beijing("2025-06-16T02:00:00Z") // 10:00
        )
        let afterAClose = WatchlistSessionOrder.orderedSymbols(
            base,
            at: beijing("2025-06-16T07:30:00Z") // 15:30, HK still open
        )
        #expect(morning == [tencent, maotai, aapl])
        #expect(afterAClose == morning)
    }
}
