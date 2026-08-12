import SwiftUI
import Charts
import PulseCore
#if canImport(AppKit)
import AppKit
#endif

/// Candlestick chart (intraday/daily/weekly/monthly) with a volume strip at the bottom.
/// The X axis uses indices rather than dates to avoid gaps from weekends/trading halts; axis labels map back to dates.
/// Mark building is extracted into @ChartContentBuilder functions: clearer structure, and it avoids type-check timeouts in deeply nested branches on SDK 27.
///
/// The chart shows a zoomable window into the loaded history (TradingView-style):
/// scroll wheel / trackpad vertical scroll zooms around the cursor, trackpad horizontal
/// scroll / shift+wheel / drag pans through history, double-click resets to the latest
/// `defaultVisibleCount` bars. Hover state lives in `CandleChartViewport` and is read only
/// by the crosshair overlays, so mouse movement never re-renders the candle marks.
public struct CandlestickChartView: View {
    let candles: [Candle]
    let palette: ChangePalette
    let period: CandlePeriod
    let market: Market?
    let highlightsExtendedHours: Bool
    let transactions: [PositionTransaction]
    let currencyCode: String?

    @State private var viewport: CandleChartViewport

    /// Pass a `viewport` to observe the zoom/pan window from outside (the detail view
    /// reads it when sharing so the card shows exactly the visible candles). The instance
    /// from the first render wins; callers must hand in a stable object.
    public init(
        candles: [Candle],
        palette: ChangePalette,
        period: CandlePeriod = .day,
        market: Market? = nil,
        highlightsExtendedHours: Bool = false,
        transactions: [PositionTransaction] = [],
        currencyCode: String? = nil,
        viewport: CandleChartViewport? = nil
    ) {
        self.candles = candles
        self.palette = palette
        self.period = period
        self.market = market
        self.highlightsExtendedHours = highlightsExtendedHours
        self.transactions = transactions
        self.currencyCode = currencyCode
        _viewport = State(initialValue: viewport ?? CandleChartViewport())
    }

    public var body: some View {
        GeometryReader { geo in
            content(containerWidth: geo.size.width)
        }
    }

    /// Fraction of the y-domain the in-pane volume band occupies. The price domain reserves
    /// slightly more (28%) below the lowest wick so the tallest bar never touches a candle.
    private static let volumeBandFraction = 0.20

    @ViewBuilder
    private func content(containerWidth: CGFloat) -> some View {
        // Derive the window once per body evaluation from live data, not from the stored
        // dataCount (which onChange only syncs after the first render).
        let range = viewport.visibleRange(dataCount: candles.count)
        let xDomain = (range.lowerBound - 1)...max(range.upperBound, 1)
        let visible = candles[safeRange: range]
        let tradeMarkers = period == .day
            ? CandleTradeMarker.dailyMarkers(
                candles: candles,
                transactions: transactions,
                market: market
            )
            : []
        let visibleTradeMarkers = tradeMarkers.filter { range.contains($0.candleIndex) }
        let showsDateOnIntradayAxis = visibleSpansMultipleDays(visible)
        // Volume shares the coordinate system as a bottom band (TradingView-style overlay):
        // one x scale means bars and candles align exactly, and the date axis sits at the
        // true bottom of the chart. Symbols without volume data reclaim the band.
        let maxVolume = visible.compactMap(\.volume).max() ?? 0
        let yDomain = yDomain(
            for: visible,
            hasBuyMarkers: visibleTradeMarkers.contains { $0.side == .buy },
            hasSellMarkers: visibleTradeMarkers.contains { $0.side == .sell },
            reserveVolumeBand: maxVolume > 0
        )
        let tradeMarkerPlacements = tradeMarkerPlacements(
            for: visibleTradeMarkers,
            visibleRange: range,
            yDomain: yDomain
        )
        // `.ratio` widths collapse to hairlines on a continuous Int scale, which turns the
        // candles into bare wicks — size the bodies explicitly from the visible density.
        let barWidth = Self.barWidth(forVisible: range.count, containerWidth: containerWidth)

        Chart {
            if highlightsExtendedHours, market == .us {
                extendedSessionMarks(range: range, slotWidth: barWidth / 0.62, yDomain: yDomain)
            }
            if maxVolume > 0 {
                volumeMarks(range: range, barWidth: barWidth, yDomain: yDomain, maxVolume: maxVolume)
            }
            candleMarks(range: range, priceDomain: yDomain, barWidth: barWidth)
            tradeMarks(tradeMarkerPlacements)
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: axisIndices(for: range)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                if let index = value.as(Int.self), let candle = candles[safe: index] {
                    AxisValueLabel(dateLabel(for: candle, showsDate: showsDateOnIntradayAxis))
                        .font(.caption2)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                if let v = value.as(Double.self) {
                    AxisValueLabel(PriceFormatter.price(v)).font(.caption2)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                CandlePriceOverlay(viewport: viewport, candles: candles, range: range,
                                   xDomain: xDomain, palette: palette, period: period,
                                   market: market, tradeMarkers: tradeMarkers,
                                   currencyCode: currencyCode,
                                   proxy: proxy, geo: geo)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active: viewport.cursorInside = true
            case .ended: viewport.cursorInside = false
            }
        }
        .gesture(dragPan)
        .onTapGesture(count: 2) { viewport.reset() }
        .onChange(of: candles.count, initial: true) { _, count in viewport.dataCount = count }
        .onChange(of: period) { _, _ in viewport.reset() }
        .onChange(of: candles) { _, _ in viewport.hoveredIndex = nil }
        .onAppear { viewport.startMonitoring() }
        .onDisappear { viewport.stopMonitoring() }
    }

    /// Mouse drag pans like grabbing the chart: content follows the cursor.
    private var dragPan: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                viewport.pan(byPoints: value.translation.width - viewport.lastDragWidth)
                viewport.lastDragWidth = value.translation.width
            }
            .onEnded { _ in viewport.lastDragWidth = 0 }
    }

    // MARK: - Marks

    /// Extended-session candles keep their normal gain/loss color. A restrained plot
    /// tint carries the session distinction without creating a third candle palette.
    @ChartContentBuilder
    private func extendedSessionMarks(
        range: Range<Int>,
        slotWidth: CGFloat,
        yDomain: ClosedRange<Double>
    ) -> some ChartContent {
        ForEach(range, id: \.self) { index in
            let kind = IntradayTradingSession.usSessionKind(for: candles[index].time)
            if kind != .regular {
                RectangleMark(
                    x: .value("Extended Session", index),
                    yStart: .value("Session Bottom", yDomain.lowerBound),
                    yEnd: .value("Session Top", yDomain.upperBound),
                    width: .fixed(max(slotWidth, 1))
                )
                .foregroundStyle(
                    kind == .pre
                        ? Color.blue.opacity(0.045)
                        : Color.purple.opacity(0.04)
                )
            }
        }
    }

    @ChartContentBuilder
    private func candleMarks(range: Range<Int>, priceDomain: ClosedRange<Double>,
                             barWidth: CGFloat) -> some ChartContent {
        ForEach(range, id: \.self) { index in
            let candle = candles[index]
            RuleMark(x: .value("i", index),
                     yStart: .value("Low", candle.low),
                     yEnd: .value("High", candle.high))
                .foregroundStyle(palette.color(isUp: candle.isUp))
                .lineStyle(StrokeStyle(lineWidth: 1))
            RectangleMark(x: .value("i", index),
                          yStart: .value("Open", bodyLow(candle)),
                          yEnd: .value("Close", bodyHigh(candle, priceDomain: priceDomain)),
                          width: .fixed(barWidth))
                .foregroundStyle(palette.color(isUp: candle.isUp))
        }
    }

    /// Volume bars scaled into the bottom band of the price domain, tallest bar = full band.
    @ChartContentBuilder
    private func volumeMarks(range: Range<Int>, barWidth: CGFloat,
                             yDomain: ClosedRange<Double>, maxVolume: Double) -> some ChartContent {
        let bandHeight = (yDomain.upperBound - yDomain.lowerBound) * Self.volumeBandFraction
        ForEach(range, id: \.self) { index in
            let candle = candles[index]
            BarMark(x: .value("i", index),
                    yStart: .value("VolumeBase", yDomain.lowerBound),
                    yEnd: .value("Volume", yDomain.lowerBound + bandHeight * (candle.volume ?? 0) / maxVolume),
                    width: .fixed(barWidth))
                .foregroundStyle(palette.color(isUp: candle.isUp).opacity(0.35))
        }
    }

    @ChartContentBuilder
    private func tradeMarks(_ placements: [TradeMarkerPlacement]) -> some ChartContent {
        ForEach(placements) { placement in
            let marker = placement.marker
            let color = tradeColor(for: marker)
            RuleMark(
                x: .value("Trade", marker.candleIndex),
                yStart: .value("Connector Start", placement.connectorStartPrice),
                yEnd: .value("Trade Marker", placement.anchorPrice)
            )
            .foregroundStyle(Color.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(
                lineWidth: 0.75,
                lineCap: .round,
                dash: [1.5, 2.5]
            ))
            PointMark(
                x: .value("Trade", marker.candleIndex),
                y: .value("Trade Marker", placement.anchorPrice)
            )
            .symbolSize(12)
            .foregroundStyle(color)
            .annotation(
                position: marker.side == .buy ? .bottom : .top,
                alignment: .center,
                spacing: 2
            ) {
                CandleTradeMarkerBadge(
                    text: markerLabel(marker),
                    color: color
                )
                .allowsHitTesting(false)
            }
        }
    }

    private func markerLabel(_ marker: CandleTradeMarker) -> String {
        let side = marker.side == .buy ? "B" : "S"
        return marker.count > 1 ? "\(side)×\(marker.count)" : side
    }

    private func tradeColor(for marker: CandleTradeMarker) -> Color {
        palette.color(isUp: marker.side == .buy)
    }

    /// Candle body / volume bar width from the visible density: 62% of the per-bar slot,
    /// clamped so deep zoom-out still shows a hairline and deep zoom-in stays proportioned.
    /// The container includes the trailing y-axis strip (~48pt); the domain pads one slot
    /// on each side of the visible range.
    private static func barWidth(forVisible count: Int, containerWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return 3 }
        let plotWidth = max(containerWidth - 48, 40)
        let slot = plotWidth / CGFloat(count + 2)
        return min(max(slot * 0.62, 1), 24)
    }

    // MARK: - Layout math

    /// Doji candles (open == close) still need a visible body: give them a tiny minimum height
    private func bodyLow(_ candle: Candle) -> Double {
        min(candle.open, candle.close)
    }

    private func bodyHigh(_ candle: Candle, priceDomain: ClosedRange<Double>) -> Double {
        let high = max(candle.open, candle.close)
        let minBody = (priceDomain.upperBound - priceDomain.lowerBound) * 0.002
        return high - bodyLow(candle) < minBody ? bodyLow(candle) + minBody : high
    }

    /// Price scale adapts to the visible window, so zooming in re-spreads the candles
    /// instead of leaving them squashed against the full-history extremes. When volume is
    /// present, the bottom reserves a band slightly taller than the volume overlay. Trade
    /// prices are intentionally excluded: a bad or split-unadjusted entry must not flatten
    /// the candles, and the precise execution price remains available in the hover detail.
    private func yDomain(
        for visible: ArraySlice<Candle>,
        hasBuyMarkers: Bool,
        hasSellMarkers: Bool,
        reserveVolumeBand: Bool
    ) -> ClosedRange<Double> {
        let lo = visible.map(\.low).min() ?? 0
        let hi = visible.map(\.high).max() ?? 1
        let span = max(hi - lo, hi * 0.001, 0.0001)
        let bottomPad: Double
        if reserveVolumeBand {
            // Leave a clean lane between the lowest wick and the volume strip for B badges.
            bottomPad = span * (hasBuyMarkers ? 0.42 : 0.28)
        } else {
            bottomPad = span * (hasBuyMarkers ? 0.16 : 0.05)
        }
        let topPad = span * (hasSellMarkers ? 0.16 : 0.05)
        return (lo - bottomPad)...(hi + topPad)
    }

    /// Badges sit outside the local candle envelope rather than at the execution price.
    /// Looking two bars in either direction keeps a wider `B×N`/`S×N` badge away from
    /// adjacent wicks. A deliberate gap before the neutral dotted connector prevents it
    /// from reading as an extension of the candle wick. The execution price remains in hover.
    private func tradeMarkerPlacements(
        for markers: [CandleTradeMarker],
        visibleRange: Range<Int>,
        yDomain: ClosedRange<Double>
    ) -> [TradeMarkerPlacement] {
        let domainSpan = yDomain.upperBound - yDomain.lowerBound
        let markerGap = domainSpan * 0.026
        let connectorGap = domainSpan * 0.008
        return markers.compactMap { marker in
            guard candles.indices.contains(marker.candleIndex) else { return nil }
            let lowerBound = max(visibleRange.lowerBound, marker.candleIndex - 2)
            let upperBound = min(visibleRange.upperBound, marker.candleIndex + 3)
            let neighbors = candles[lowerBound..<upperBound]
            let anchorPrice: Double
            let connectorStartPrice: Double
            switch marker.side {
            case .buy:
                connectorStartPrice = candles[marker.candleIndex].low - connectorGap
                anchorPrice = (neighbors.map(\.low).min() ?? candles[marker.candleIndex].low) - markerGap
            case .sell:
                connectorStartPrice = candles[marker.candleIndex].high + connectorGap
                anchorPrice = (neighbors.map(\.high).max() ?? candles[marker.candleIndex].high) + markerGap
            }
            return TradeMarkerPlacement(
                marker: marker,
                connectorStartPrice: connectorStartPrice,
                anchorPrice: anchorPrice
            )
        }
    }

    private func axisIndices(for range: Range<Int>) -> [Int] {
        guard range.count > 1 else { return Array(range) }
        let step = max(range.count / 4, 1)
        return Array(stride(from: range.lowerBound, to: range.upperBound, by: step))
    }

    private func dateLabel(for candle: Candle, showsDate: Bool) -> String {
        switch period {
        case .minute1, .minute5, .minute15, .minute30, .hour1:
            CandleChartTimeFormatter.string(
                from: candle.time,
                market: market,
                format: showsDate ? "MM/dd H:mm" : "H:mm"
            )
        case .month, .week:
            candle.time.formatted(.dateTime.year(.twoDigits).month(.twoDigits))
        case .day:
            candle.time.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        }
    }

    private func visibleSpansMultipleDays(_ visible: ArraySlice<Candle>) -> Bool {
        guard period.isMinuteK, let first = visible.first, let last = visible.last else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market?.timeZone ?? .current
        return !calendar.isDate(first.time, inSameDayAs: last.time)
    }
}

private struct TradeMarkerPlacement: Identifiable {
    var marker: CandleTradeMarker
    var connectorStartPrice: Double
    var anchorPrice: Double

    var id: CandleTradeMarker.ID { marker.id }
}

// MARK: - Viewport (zoom/pan/hover state)

/// Window state plus the AppKit event plumbing behind wheel-zoom and scroll-pan.
/// `visibleCount`/`rightOffset` are observed (the chart re-renders on zoom/pan);
/// `hoveredIndex` is observed only by the crosshair overlays. Everything the event
/// handlers need between renders (data count, plot width, cursor location) is
/// intentionally unobserved.
@MainActor
@Observable
public final class CandleChartViewport {
    static let defaultVisibleCount = 60
    static let minVisibleCount = 20

    public init() {}

    var visibleCount = CandleChartViewport.defaultVisibleCount
    /// Bars hidden to the right of the window; 0 = pinned to the latest bar.
    var rightOffset = 0
    var hoveredIndex: Int?

    @ObservationIgnored var dataCount = 0
    @ObservationIgnored var plotWidth: CGFloat = 300
    @ObservationIgnored var cursorInside = false
    @ObservationIgnored var lastDragWidth: CGFloat = 0
    @ObservationIgnored private var panRemainder: Double = 0
    @ObservationIgnored private var monitor: Any?

    public func visibleRange(dataCount: Int) -> Range<Int> {
        guard dataCount > 0 else { return 0..<0 }
        let count = min(visibleCount, dataCount)
        let maxOffset = dataCount - count
        let end = dataCount - 1 - min(max(rightOffset, 0), maxOffset)
        return (end - count + 1)..<(end + 1)
    }

    func reset() {
        visibleCount = Self.defaultVisibleCount
        rightOffset = 0
        panRemainder = 0
    }

    /// factor > 1 zooms in (fewer bars). The bar under the cursor keeps its screen
    /// position, so wheel-zoom feels anchored like TradingView.
    func zoom(by factor: Double) {
        guard dataCount > 0, factor > 0 else { return }
        let range = visibleRange(dataCount: dataCount)
        let oldCount = range.count
        let newCount = min(max(Int((Double(oldCount) / factor).rounded()), Self.minVisibleCount), dataCount)
        guard newCount != oldCount else { return }
        let anchor = hoveredIndex.map { min(max($0, range.lowerBound), range.upperBound - 1) }
            ?? range.upperBound - 1
        let fraction = oldCount > 1
            ? Double(anchor - range.lowerBound) / Double(oldCount - 1)
            : 1
        let newEnd = anchor + Int((Double(newCount - 1) * (1 - fraction)).rounded())
        visibleCount = newCount
        rightOffset = min(max(dataCount - 1 - newEnd, 0), dataCount - newCount)
    }

    /// Positive points pan toward older bars (matches AppKit scroll semantics and
    /// grab-drag direction). Sub-bar remainders accumulate so slow pans stay smooth.
    func pan(byPoints points: CGFloat) {
        guard dataCount > 0 else { return }
        let count = visibleRange(dataCount: dataCount).count
        panRemainder += Double(points) * Double(count) / Double(max(plotWidth, 1))
        let whole = Int(panRemainder.rounded(.towardZero))
        guard whole != 0 else { return }
        panRemainder -= Double(whole)
        rightOffset = min(max(rightOffset + whole, 0), max(dataCount - count, 0))
    }

    #if canImport(AppKit)
    /// Local monitor instead of a gesture: SwiftUI has no scroll-wheel modifier on macOS,
    /// and taking the wheel for zoom must not fight a scrollable ancestor. `cursorInside`
    /// (maintained by onContinuousHover) gates which events belong to the chart.
    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            // Monitors fire on the main thread; only the Sendable Bool crosses the boundary.
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        cursorInside = false
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard cursorInside, dataCount > 0 else { return false }
        switch event.type {
        case .magnify:
            zoom(by: 1 + event.magnification)
            return true
        case .scrollWheel:
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            if event.modifierFlags.contains(.shift) {
                // Shift turns the wheel into a pan; mice report the swapped axis in dy.
                pan(byPoints: dx != 0 ? dx : dy)
            } else if abs(dx) > abs(dy) {
                pan(byPoints: dx)
            } else if dy != 0 {
                zoom(by: exp(dy * 0.006))
            }
            return true
        default:
            return false
        }
    }
    #else
    func startMonitoring() {}
    func stopMonitoring() {}
    #endif
}

// MARK: - Crosshair overlays

/// Price-pane crosshair, OHLC readout and axis tags. A separate view so hover-state
/// changes re-render only this overlay, never the candle marks behind it.
private struct CandlePriceOverlay: View {
    let viewport: CandleChartViewport
    let candles: [Candle]
    let range: Range<Int>
    let xDomain: ClosedRange<Int>
    let palette: ChangePalette
    let period: CandlePeriod
    let market: Market?
    let tradeMarkers: [CandleTradeMarker]
    let currencyCode: String?
    let proxy: ChartProxy
    let geo: GeometryProxy

    var body: some View {
        let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
        ZStack(alignment: .topLeading) {
            CandleHoverCatcher(viewport: viewport, range: range, xDomain: xDomain, plot: plot)
            if let index = viewport.hoveredIndex, let candle = candles[safe: index],
               let xPos = proxy.position(forX: index),
               let yPos = proxy.position(forY: candle.close) {
                let px = plot.origin.x + xPos
                let py = plot.origin.y + min(max(yPos, 0), plot.height)
                ChartCrosshair.lines(px: px, py: py, in: plot)
                priceTag(for: candle, py: py)
                readout(
                    for: candle,
                    previous: candles[safe: index - 1],
                    tradeMarkers: tradeMarkers.filter { $0.candleIndex == index }
                )
                    .padding(4)
                    .frame(width: plot.width, height: plot.height,
                           alignment: px > plot.midX ? .topLeading : .topTrailing)
                    .offset(x: plot.origin.x, y: plot.origin.y)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: plot.width, initial: true) { _, width in
            // Pan sensitivity needs the plot width; unobserved, so no render feedback loop.
            viewport.plotWidth = width
        }
    }

    private func priceTag(for candle: Candle, py: CGFloat) -> some View {
        let text = PriceFormatter.price(candle.close)
        return CrosshairTag(text: text)
            .position(x: geo.size.width - ChartCrosshair.tagWidth(text) / 2, y: py)
    }

    /// OHLC + volume readout, docked to the top corner away from the cursor.
    private func readout(
        for candle: Candle,
        previous: Candle?,
        tradeMarkers: [CandleTradeMarker]
    ) -> some View {
        let base = previous?.close ?? candle.open
        let changePercent = base == 0 ? 0 : (candle.close - base) / base * 100
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(readoutDateLabel(for: candle))
                    .foregroundStyle(.secondary)
                Text(PriceFormatter.percent(changePercent))
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.color(for: changePercent))
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                GridRow {
                    readoutValue(PulseLocalization.localizedString("chart.open"), PriceFormatter.price(candle.open))
                    readoutValue(PulseLocalization.localizedString("chart.high"), PriceFormatter.price(candle.high))
                }
                GridRow {
                    readoutValue(PulseLocalization.localizedString("chart.low"), PriceFormatter.price(candle.low))
                    readoutValue(PulseLocalization.localizedString("chart.close"), PriceFormatter.price(candle.close))
                }
                if let volume = candle.volume {
                    GridRow {
                        readoutValue(PulseLocalization.localizedString("chart.volume"), PriceFormatter.compact(volume))
                    }
                }
            }
            if !tradeMarkers.isEmpty {
                Divider()
                    .padding(.vertical, 1)
                ForEach(tradeMarkers) { marker in
                    CandleTradeMarkerReadout(
                        marker: marker,
                        palette: palette,
                        currencyCode: currencyCode
                    )
                }
            }
        }
        .font(.system(size: 9).monospacedDigit())
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.thickMaterial))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.separator.opacity(0.5), lineWidth: 0.5))
        .fixedSize()
    }

    private func readoutValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.primary)
        }
    }

    private func readoutDateLabel(for candle: Candle) -> String {
        switch period {
        case .minute1, .minute5, .minute15, .minute30, .hour1:
            CandleChartTimeFormatter.string(
                from: candle.time,
                market: market,
                format: "yyyy/MM/dd H:mm"
            )
        case .month:
            candle.time.formatted(.dateTime.year().month(.twoDigits))
        case .week:
            weekRangeLabel(for: candle.time)
        case .day:
            candle.time.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        }
    }

    /// A weekly bar covers a trading week, so the readout shows the Monday–Friday range
    /// instead of the bar's raw timestamp (whichever day the provider stamps it with).
    private func weekRangeLabel(for date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)  // Monday-based weeks
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let end = calendar.date(byAdding: .day, value: 4, to: start) ?? date
        let startLabel = start.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        let endLabel = end.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        return "\(startLabel)–\(endLabel)"
    }
}

private struct CandleTradeMarkerBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 7.5, weight: .bold, design: .rounded).monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, text.count > 1 ? 4 : 0)
            .frame(minWidth: 14)
            .frame(height: 14)
            .background(color, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.16), radius: 1, y: 0.5)
    }
}

private struct CandleTradeMarkerReadout: View {
    let marker: CandleTradeMarker
    let palette: ChangePalette
    let currencyCode: String?

    private var sideKey: String {
        marker.side == .buy ? "trade.buy" : "trade.sell"
    }

    private var sideText: String {
        PulseLocalization.localizedString(sideKey)
    }

    private var badgeText: String {
        let side = marker.side == .buy ? "B" : "S"
        return marker.count > 1 ? "\(side)×\(marker.count)" : side
    }

    private var color: Color {
        palette.color(isUp: marker.side == .buy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                CandleTradeMarkerBadge(text: badgeText, color: color)
                    .scaleEffect(0.86, anchor: .leading)
                    .frame(width: badgeText.count > 1 ? 23 : 14, height: 12, alignment: .leading)
                Text(sideText)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                GridRow {
                    value(
                        PulseLocalization.localizedString("trade.price"),
                        PriceFormatter.price(marker.averagePrice)
                    )
                    value(
                        PulseLocalization.localizedString("position.quantity"),
                        PriceFormatter.quantity(marker.totalQuantity)
                    )
                }
                GridRow {
                    value(
                        PulseLocalization.localizedString("trade.amount"),
                        PriceFormatter.money(marker.totalAmount, currencyCode: currencyCode)
                    )
                }
            }
        }
    }

    private func value(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.primary)
        }
    }
}

@MainActor
private enum CandleChartTimeFormatter {
    private static var cache: [String: DateFormatter] = [:]

    static func string(from date: Date, market: Market?, format: String) -> String {
        let timeZone = market?.timeZone ?? .current
        let key = "\(timeZone.identifier)|\(format)"
        let formatter: DateFormatter
        if let cached = cache[key] {
            formatter = cached
        } else {
            let created = DateFormatter()
            created.locale = Locale(identifier: "en_US_POSIX")
            created.timeZone = timeZone
            created.dateFormat = format
            cache[key] = created
            formatter = created
        }
        return formatter.string(from: date)
    }
}

/// Transparent layer that tracks the cursor and feeds the shared hovered index.
private struct CandleHoverCatcher: View {
    let viewport: CandleChartViewport
    let range: Range<Int>
    let xDomain: ClosedRange<Int>
    let plot: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    viewport.hoveredIndex = index(at: point)
                case .ended:
                    viewport.hoveredIndex = nil
                }
            }
    }

    /// Invert the linear index scale by hand: `proxy.value(atX:)` on an Int scale truncates,
    /// which would make the snap lag half a candle behind the cursor.
    private func index(at point: CGPoint) -> Int? {
        guard !range.isEmpty, plot.width > 0,
              plot.insetBy(dx: -2, dy: -4).contains(point) else { return nil }
        let rel = (point.x - plot.origin.x) / plot.width
        let raw = Double(xDomain.lowerBound) + rel * Double(xDomain.upperBound - xDomain.lowerBound)
        return min(max(Int(raw.rounded()), range.lowerBound), range.upperBound - 1)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    subscript(safeRange range: Range<Int>) -> ArraySlice<Element> {
        let clamped = range.clamped(to: indices.lowerBound..<indices.upperBound)
        return self[clamped]
    }
}
