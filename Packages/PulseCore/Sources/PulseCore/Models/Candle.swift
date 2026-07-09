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
    case day
    case week
    case month

    public var displayName: String {
        switch self {
        case .minute1: PulseLocalization.localizedString("period.minute1")
        case .minute5: PulseLocalization.localizedString("period.minute5")
        case .day: PulseLocalization.localizedString("period.day")
        case .week: PulseLocalization.localizedString("period.week")
        case .month: PulseLocalization.localizedString("period.month")
        }
    }

    public var isIntraday: Bool { self == .minute1 || self == .minute5 }
}
