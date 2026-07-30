import Foundation

public struct Candle: Codable, Sendable, Hashable {
    public var time: Date
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    public var volume: Double?

    public init(time: Date, open: Double, high: Double, low: Double, close: Double, volume: Double? = nil) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }

    public var isUp: Bool { close >= open }
}

public enum CandlePeriod: String, Codable, Sendable, CaseIterable, Hashable {
    case minute1
    case minute5
    case minute15
    case minute30
    case hour1
    case day
    case week
    case month

    public var displayName: String {
        switch self {
        case .minute1: PulseLocalization.localizedString("period.minute1")
        case .minute5: PulseLocalization.localizedString("period.minute5")
        case .minute15: PulseLocalization.localizedString("period.minute15")
        case .minute30: PulseLocalization.localizedString("period.minute30")
        case .hour1: PulseLocalization.localizedString("period.hour1")
        case .day: PulseLocalization.localizedString("period.day")
        case .week: PulseLocalization.localizedString("period.week")
        case .month: PulseLocalization.localizedString("period.month")
        }
    }

    /// Every period whose bars live inside an exchange trading day.
    public var isIntraday: Bool {
        switch self {
        case .minute1, .minute5, .minute15, .minute30, .hour1:
            true
        case .day, .week, .month:
            false
        }
    }

    /// Intraday candlestick periods shown under the resolution menu. The 1-minute
    /// period remains the fixed-session price trend rather than a candlestick chart.
    public var isMinuteK: Bool {
        switch self {
        case .minute5, .minute15, .minute30, .hour1:
            true
        case .minute1, .day, .week, .month:
            false
        }
    }

    /// Bar width in trading minutes, used by providers that aggregate 1-minute rows.
    public var intradayMinutes: Int? {
        switch self {
        case .minute1: 1
        case .minute5: 5
        case .minute15: 15
        case .minute30: 30
        case .hour1: 60
        case .day, .week, .month: nil
        }
    }
}
