import Foundation
import PulseCore

public enum PriceFormatter {
    /// Stock price: always 2 decimal places
    public static func price(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).grouping(.never))
    }

    /// Percent change: "+1.23%" / "-0.95%" / "0.00%"
    public static func percent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + value.formatted(.number.precision(.fractionLength(2))) + "%"
    }

    /// Price change (signed)
    public static func change(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + price(value)
    }

    /// Compact volume/turnover display using CJK scale units: wan (10^4) / yi (10^8)
    public static func compact(_ value: Double) -> String {
        switch value {
        case 1e8...: (value / 1e8).formatted(.number.precision(.fractionLength(2))) + "亿"
        case 1e4...: (value / 1e4).formatted(.number.precision(.fractionLength(1))) + "万"
        default: value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    /// Up/down arrow for the menu bar
    public static func arrow(_ change: Double) -> String {
        change > 0 ? "▲" : (change < 0 ? "▼" : "–")
    }
}
