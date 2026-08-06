import Foundation
import Testing
@testable import PulseCore

@Suite("Trading calendar session priority")
struct TradingCalendarSessionPriorityTests {
    private func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? .distantPast
    }

    @Test("A-shares keep priority through lunch")
    func chinaLunchKeepsPriority() {
        // 12:00 Shanghai on a weekday
        let lunch = instant("2025-06-16T04:00:00Z")
        #expect(TradingCalendar.state(of: .sh, at: lunch) == .lunchBreak)
        #expect(TradingCalendar.hasSessionPriority(.sh, at: lunch))
        #expect(TradingCalendar.hasSessionPriority(.sz, at: lunch))
        #expect(!TradingCalendar.isActive(.sh, at: lunch))
    }

    @Test("Hong Kong keeps priority through lunch")
    func hongKongLunchKeepsPriority() {
        let lunch = instant("2025-06-16T04:30:00Z") // 12:30 HKT
        #expect(TradingCalendar.state(of: .hk, at: lunch) == .lunchBreak)
        #expect(TradingCalendar.hasSessionPriority(.hk, at: lunch))
    }

    @Test("US only prioritizes the regular session")
    func usRegularOnly() {
        let pre = instant("2025-06-16T10:00:00Z") // 06:00 ET
        let regular = instant("2025-06-16T15:00:00Z") // 11:00 ET
        let post = instant("2025-06-16T21:00:00Z") // 17:00 ET
        #expect(TradingCalendar.state(of: .us, at: pre) == .preMarket)
        #expect(!TradingCalendar.hasSessionPriority(.us, at: pre))
        #expect(TradingCalendar.hasSessionPriority(.us, at: regular))
        #expect(TradingCalendar.state(of: .us, at: post) == .postMarket)
        #expect(!TradingCalendar.hasSessionPriority(.us, at: post))
    }

    @Test("Crypto never receives session priority")
    func cryptoExcluded() {
        #expect(TradingCalendar.state(of: .crypto) == .regular)
        #expect(!TradingCalendar.hasSessionPriority(.crypto))
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

    @Test("Open market blocks float above closed ones without interleaving")
    func openBlocksFloat() {
        // Base order deliberately interleaves markets.
        let base = [aapl, maotai, tencent, pingAn, tsla, btc]
        let ordered = WatchlistSessionOrder.orderedSymbols(
            base,
            pinned: [],
            at: .distantPast,
            priority: { market, _ in market == .sh || market == .sz || market == .hk }
        )
        #expect(ordered == [maotai, pingAn, tencent, aapl, tsla, btc])
    }

    @Test("Pins stay inside their market block")
    func pinsWithinBlock() {
        let base = [aapl, maotai, tencent, pingAn, tsla]
        let ordered = WatchlistSessionOrder.orderedSymbols(
            base,
            pinned: [tsla, pingAn],
            at: .distantPast,
            priority: { market, _ in market == .sh || market == .sz }
        )
        // Open China A: pinned pingAn first, then maotai.
        // Closed blocks keep MarketBlock order: HK then US (tsla pinned before aapl).
        #expect(ordered == [pingAn, maotai, tencent, tsla, aapl])
    }

    @Test("Crypto stays with the non-priority tier even when always regular")
    func cryptoNeverFloats() {
        let base = [btc, aapl, maotai]
        let ordered = WatchlistSessionOrder.orderedSymbols(
            base,
            pinned: [],
            at: .distantPast,
            priority: TradingCalendar.hasSessionPriority
        )
        // With distantPast (closed everywhere), block order is chinaA → hk → us → crypto.
        #expect(ordered == [maotai, aapl, btc])
    }

    @Test("Relative order inside a market is preserved from the base sequence")
    func preservesRelativeOrder() {
        let base = [tsla, aapl, pingAn, maotai]
        let ordered = WatchlistSessionOrder.orderedSymbols(
            base,
            pinned: [],
            at: .distantPast,
            priority: { _, _ in false }
        )
        #expect(ordered == [pingAn, maotai, tsla, aapl])
    }
}
