import Foundation

/// Rebuilds a candle series at a coarser period.
///
/// Sources rarely serve every resolution Pulse offers: Sina publishes daily bars
/// and a one-day minute line, the Shanghai Gold Exchange only daily, Naver daily
/// and one-minute. Each of those becomes the base series that the missing
/// periods are folded out of.
///
/// Bucketing reads wall-clock time, so the series' own exchange time zone has to
/// come with it: a Seoul minute bar bucketed on Shanghai hours would still land
/// correctly today, but only because the two offsets differ by a whole hour.
enum CandleResampler {
    static func resample(
        _ candles: [Candle],
        into period: CandlePeriod,
        timeZone: TimeZone
    ) -> [Candle] {
        guard !candles.isEmpty else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let bucket: (Candle) -> Date?
        switch period {
        case .minute1, .day:
            return candles
        case .minute5, .minute15, .minute30, .hour1:
            guard let span = period.intradayMinutes, span > 1 else { return candles }
            bucket = { candle in
                let minutes = calendar.component(.hour, from: candle.time) * 60
                    + calendar.component(.minute, from: candle.time)
                let start = calendar.startOfDay(for: candle.time)
                return calendar.date(byAdding: .minute, value: (minutes / span) * span, to: start)
            }
        case .week:
            bucket = { candle in
                calendar.dateInterval(of: .weekOfYear, for: candle.time)?.start
            }
        case .month:
            bucket = { candle in
                calendar.dateInterval(of: .month, for: candle.time)?.start
            }
        }

        return Dictionary(grouping: candles) { bucket($0) ?? $0.time }
            .compactMap { start, group -> Candle? in
                let sorted = group.sorted { $0.time < $1.time }
                guard let first = sorted.first, let last = sorted.last else { return nil }
                let volumes = sorted.compactMap(\.volume)
                return Candle(
                    time: start,
                    open: first.open,
                    high: sorted.map(\.high).max() ?? first.high,
                    low: sorted.map(\.low).min() ?? first.low,
                    close: last.close,
                    volume: volumes.isEmpty ? nil : volumes.reduce(0, +)
                )
            }
            .sorted { $0.time < $1.time }
    }
}
