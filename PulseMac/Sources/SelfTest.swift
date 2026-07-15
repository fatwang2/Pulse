import AppKit
import Foundation
import SwiftUI
import PulseCore

/// In-sandbox data pipeline self-test: `./Pulse.app/Contents/MacOS/Pulse --selftest`
/// Unlike the CLI unit tests, this runs in the app's real sandbox/signing/network environment.
enum SelfTest {
    static func runIfRequested() {
        if CommandLine.arguments.contains("--share-selftest") {
            Task { @MainActor in
                exit(runShareImageTest() ? 0 : 1)
            }
            return
        }

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
            await report("candles(600519, minute1 Tencent)") {
                let r = try await provider.candles(
                    for: SymbolID(market: .sh, code: "600519"), period: .minute1, count: 60
                )
                return "\(r.count) points, latest \(r.last?.time.formatted(date: .omitted, time: .standard) ?? "—")"
            }
            await report("candles(AAPL, day)") {
                let r = try await provider.candles(for: SymbolID(market: .us, code: "AAPL"), period: .day, count: 30)
                return "\(r.count) candles, latest close \(r.last?.close ?? 0)"
            }

            // Reproduce a mixed-provider flow: Tencent supplies A-share quotes/minutes; Yahoo covers other candles.
            await report("user flow: add watchlist(000847.SH/700.HK/80700.HK) -> sparkline -> search again") {
                let flow = CompositeProvider(providers: [TencentProvider(), YahooProvider()])
                let added = [
                    SymbolID(market: .sh, code: "000847"),
                    SymbolID(market: .hk, code: "700"),
                    SymbolID(market: .hk, code: "80700"),
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

    @MainActor
    private static func runShareImageTest() -> Bool {
        do {
            let metricTestItem = WatchItem(
                symbol: SymbolID(market: .us, code: "AAPL"),
                displayName: "Apple",
                lots: [CostLot(price: 200, quantity: 10)]
            )
            let metricTestQuote = Quote(
                symbol: metricTestItem.symbol,
                price: 231.42,
                previousClose: 228.50,
                currencyCode: "USD"
            )
            guard let metricTestPosition = PositionMetrics(item: metricTestItem, quote: metricTestQuote) else {
                throw ShareImageError.renderingFailed
            }
            let percentDisplay = WatchRowMetricDisplay.resolve(
                quote: metricTestQuote,
                metrics: metricTestPosition,
                mode: .changePercent,
                item: metricTestItem
            )
            let todayDisplay = WatchRowMetricDisplay.resolve(
                quote: metricTestQuote,
                metrics: metricTestPosition,
                mode: .todayPnL,
                item: metricTestItem
            )
            let totalDisplay = WatchRowMetricDisplay.resolve(
                quote: metricTestQuote,
                metrics: metricTestPosition,
                mode: .totalPnL,
                item: metricTestItem
            )
            guard percentDisplay.text.hasSuffix("%"),
                  todayDisplay.text.contains("$"),
                  totalDisplay.text.contains("$"),
                  todayDisplay.colorValue == metricTestPosition.todayPnL,
                  totalDisplay.colorValue == metricTestPosition.totalPnL else {
                throw ShareImageError.renderingFailed
            }

            func trendCandles(_ values: [Double], market: Market) -> [Candle] {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = market.timeZone
                let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)) ?? .now
                let startHour = market == .crypto ? 0 : 9
                let startMinute = market == .crypto ? 0 : 30
                let start = calendar.date(
                    bySettingHour: startHour,
                    minute: startMinute,
                    second: 0,
                    of: day
                ) ?? day
                return values.enumerated().map { index, close in
                    Candle(
                        time: start.addingTimeInterval(Double(index) * 60),
                        open: close,
                        high: close,
                        low: close,
                        close: close
                    )
                }
            }

            let snapshot = WatchlistShareSnapshot(
                rows: [
                    .init(
                        id: SymbolID(market: .us, code: "AAPL"),
                        name: "Apple",
                        market: .us,
                        symbolCode: "AAPL",
                        priceText: "231.42",
                        metricText: "+$29.20",
                        metricColorValue: 2.92,
                        change: 2.92,
                        previousClose: 228.50,
                        sessionLabel: nil,
                        sparkline: trendCandles([228.5, 229.2, 228.9, 230.4, 231.0, 231.42], market: .us)
                    ),
                    .init(
                        id: SymbolID(market: .hk, code: "700"),
                        name: "腾讯控股",
                        market: .hk,
                        symbolCode: "700",
                        priceText: "542.50",
                        metricText: "+HK$45.00",
                        metricColorValue: 4.50,
                        change: 4.50,
                        previousClose: 538.00,
                        sessionLabel: nil,
                        sparkline: trendCandles([538, 539, 537.8, 540.2, 541.6, 542.5], market: .hk)
                    ),
                    .init(
                        id: SymbolID(market: .sh, code: "600519"),
                        name: "贵州茅台",
                        market: .sh,
                        symbolCode: "600519",
                        priceText: "1,482.30",
                        metricText: "-¥54.00",
                        metricColorValue: -5.40,
                        change: -5.40,
                        previousClose: 1487.70,
                        sessionLabel: nil,
                        sparkline: trendCandles([1487.7, 1485.2, 1486.4, 1483.8, 1484.5, 1482.3], market: .sh)
                    ),
                    .init(
                        id: SymbolID(market: .us, code: "MSFT"),
                        name: "Microsoft",
                        market: .us,
                        symbolCode: "MSFT",
                        priceText: "497.72",
                        metricText: "+$23.40",
                        metricColorValue: 2.34,
                        change: 2.34,
                        previousClose: 495.38,
                        sessionLabel: nil,
                        sparkline: trendCandles([495.4, 496.1, 495.8, 496.9, 497.1, 497.72], market: .us)
                    ),
                    .init(
                        id: SymbolID(market: .us, code: "NVDA"),
                        name: "NVIDIA",
                        market: .us,
                        symbolCode: "NVDA",
                        priceText: "164.92",
                        metricText: "-$10.30",
                        metricColorValue: -1.03,
                        change: -1.03,
                        previousClose: 165.95,
                        sessionLabel: nil,
                        sparkline: trendCandles([165.9, 165.5, 165.8, 165.1, 164.7, 164.92], market: .us)
                    ),
                    .init(
                        id: SymbolID(market: .hk, code: "9988"),
                        name: "阿里巴巴-W",
                        market: .hk,
                        symbolCode: "9988",
                        priceText: "111.80",
                        metricText: "+HK$16.00",
                        metricColorValue: 1.60,
                        change: 1.60,
                        previousClose: 110.20,
                        sessionLabel: nil,
                        sparkline: trendCandles([110.2, 110.6, 110.4, 111.0, 111.5, 111.8], market: .hk)
                    ),
                    .init(
                        id: SymbolID(market: .crypto, code: "BTC-USD"),
                        name: "Bitcoin USD",
                        market: .crypto,
                        symbolCode: "BTC-USD",
                        priceText: "116,420.00",
                        metricText: "+$2,460.00",
                        metricColorValue: 2460,
                        change: 2460,
                        previousClose: 113960,
                        sessionLabel: nil,
                        sparkline: trendCandles([113960, 114800, 114300, 115400, 116000, 116420], market: .crypto)
                    ),
                ],
                redUp: true,
                updatedAtText: PulseLocalization.localizedString("refresh.updatedAt", "09:45")
            )
            let card = PulseShareCard(
                metadata: PulseShareCardMetadata(updatedAtText: snapshot.updatedAtText)
            ) {
                WatchlistShareContent(snapshot: snapshot)
            }
            let artifact = try ShareImageRenderer.render(
                card,
                configuration: .socialPortrait(
                    height: snapshot.preferredImageHeight,
                    colorScheme: .light,
                    locale: Locale(identifier: "en")
                )
            )

            let pasteboard = NSPasteboard.withUniqueName()
            try ClipboardImageExporter.write(artifact, to: pasteboard)
            guard pasteboard.data(forType: .png) != nil,
                  pasteboard.data(forType: .tiff) != nil,
                  let bitmap = NSBitmapImageRep(data: artifact.pngData),
                  bitmap.pixelsWide == 1080,
                  bitmap.pixelsHigh == 1350 else {
                throw ShareImageError.clipboardWriteFailed
            }

            let shortSnapshot = WatchlistShareSnapshot(
                rows: Array(snapshot.rows.prefix(1)),
                redUp: snapshot.redUp,
                updatedAtText: snapshot.updatedAtText
            )
            guard snapshot.titleColumnWidth > shortSnapshot.titleColumnWidth,
                  snapshot.metricColumnWidth > shortSnapshot.metricColumnWidth else {
                throw ShareImageError.renderingFailed
            }
            let shortCard = PulseShareCard(
                metadata: PulseShareCardMetadata(updatedAtText: shortSnapshot.updatedAtText)
            ) {
                WatchlistShareContent(snapshot: shortSnapshot)
            }
            let shortArtifact = try ShareImageRenderer.render(
                shortCard,
                configuration: .socialPortrait(
                    height: shortSnapshot.preferredImageHeight,
                    colorScheme: .light,
                    locale: Locale(identifier: "en")
                )
            )
            guard let shortBitmap = NSBitmapImageRep(data: shortArtifact.pngData),
                  shortBitmap.pixelsWide == 1080,
                  shortBitmap.pixelsHigh == 720 else {
                throw ShareImageError.renderingFailed
            }

            let detailQuote = Quote(
                symbol: metricTestItem.symbol,
                name: "Apple",
                price: 231.42,
                previousClose: 228.50,
                open: 229.10,
                high: 232.18,
                low: 227.82,
                volume: 48_260_000,
                currencyCode: "USD",
                marketState: .regular
            )
            let detailValues = (0..<120).map { index in
                let minute = Double(index)
                return 228.5 + minute * 0.024 + sin(minute / 8) * 0.72 + sin(minute / 2.7) * 0.18
            }
            let detailCandles = trendCandles(detailValues, market: .us)
            let detailSnapshot = DetailShareSnapshot(
                symbol: metricTestItem.symbol,
                name: "Apple",
                quote: detailQuote,
                period: .minute1,
                candles: detailCandles,
                redUp: true,
                updatedAtText: PulseLocalization.localizedString("refresh.updatedAt", "09:45")
            )
            let detailCard = PulseShareCard(
                metadata: PulseShareCardMetadata(updatedAtText: detailSnapshot.updatedAtText)
            ) {
                DetailShareContent(snapshot: detailSnapshot)
            }
            let detailArtifact = try ShareImageRenderer.render(
                detailCard,
                configuration: .socialPortrait(
                    height: detailSnapshot.preferredImageHeight,
                    colorScheme: .light,
                    locale: Locale(identifier: "en")
                )
            )
            guard let detailBitmap = NSBitmapImageRep(data: detailArtifact.pngData),
                  detailBitmap.pixelsWide == 1080,
                  detailBitmap.pixelsHigh == 1024 else {
                throw ShareImageError.renderingFailed
            }

            let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pulse-share-selftest.png")
            try artifact.pngData.write(to: outputURL, options: .atomic)
            let shortOutputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pulse-share-selftest-short.png")
            try shortArtifact.pngData.write(to: shortOutputURL, options: .atomic)
            let detailOutputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pulse-detail-share-selftest.png")
            try detailArtifact.pngData.write(to: detailOutputURL, options: .atomic)
            print(
                "SHARE_SELFTEST: ✅ PNG/TIFF copied to isolated pasteboard, "
                    + "images=\(shortBitmap.pixelsWide)x\(shortBitmap.pixelsHigh)..."
                    + "\(bitmap.pixelsWide)x\(bitmap.pixelsHigh), detail="
                    + "\(detailBitmap.pixelsWide)x\(detailBitmap.pixelsHigh), outputs="
                    + "\(shortOutputURL.path),\(outputURL.path),\(detailOutputURL.path)"
            )
            return true
        } catch {
            print("SHARE_SELFTEST: ❌ \(error)")
            return false
        }
    }
}
