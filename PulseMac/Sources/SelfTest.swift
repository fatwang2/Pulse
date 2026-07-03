import Foundation
import PulseCore

/// In-sandbox data pipeline self-test: `./Pulse.app/Contents/MacOS/Pulse --selftest`
/// Unlike the CLI unit tests, this runs in the app's real sandbox/signing/network environment.
enum SelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        Task.detached {
            let provider = CompositeProvider(providers: [TencentProvider(), YahooProvider()])

            func report(_ label: String, _ operation: () async throws -> String) async {
                do {
                    print("SELFTEST \(label): ✅ \(try await operation())")
                } catch {
                    print("SELFTEST \(label): ❌ \(error)")
                }
            }

            await report("search(AAPL)") {
                let r = try await provider.search("AAPL")
                return "\(r.count) results — \(r.prefix(3).map { "\($0.name)(\($0.symbol))" }.joined(separator: ", "))"
            }
            await report("search(腾讯)") {
                let r = try await provider.search("腾讯")
                return "\(r.count) results — \(r.prefix(3).map { "\($0.name)(\($0.symbol))" }.joined(separator: ", "))"
            }
            await report("quotes(600519/700/AAPL)") {
                let r = try await provider.quotes(for: [
                    SymbolID(market: .sh, code: "600519"),
                    SymbolID(market: .hk, code: "700"),
                    SymbolID(market: .us, code: "AAPL"),
                ])
                return r.map { "\($0.symbol)=\($0.price)" }.joined(separator: ", ")
            }
            await report("candles(AAPL, day)") {
                let r = try await provider.candles(for: SymbolID(market: .us, code: "AAPL"), period: .day, count: 30)
                return "\(r.count) candles, latest close \(r.last?.close ?? 0)"
            }

            // Reproduce a user flow: add symbols from the Tencent (Chinese-name) search results that Yahoo doesn't cover
            // -> quotes -> fetch sparklines one by one (including symbols Yahoo lacks) -> search again; health must not degrade
            await report("user flow: add watchlist(000847.SH/700.HK/80700.HK) -> sparkline -> search again") {
                let flow = CompositeProvider(providers: [TencentProvider(), YahooProvider()])
                let added = [
                    SymbolID(market: .sh, code: "000847"),   // Tencent Ji'an Index: not available on Yahoo
                    SymbolID(market: .hk, code: "700"),
                    SymbolID(market: .hk, code: "80700"),    // RMB counter: not available on Yahoo
                ]
                let quotes = try await flow.quotes(for: added)
                var sparkOK = 0
                for symbol in added {
                    if let candles = try? await flow.candles(for: symbol, period: .minute5, count: 60),
                       !candles.isEmpty { sparkOK += 1 }
                }
                let again = try await flow.search("苹果")
                let health = await flow.healthReport()
                return "quotes \(quotes.count)/3, sparkline \(sparkOK)/3, re-search \(again.count) results, health=\(health)"
            }
            exit(0)
        }
    }
}
