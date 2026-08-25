import Foundation
import PulseCore

public enum PriceFormatter {
    /// How many fraction digits a price may carry on screen for this market.
    ///
    /// The range is inclusive: the lower bound is always shown (so columns stay
    /// aligned), and the upper bound is used when the print actually needs it.
    /// That is what lets a HK penny stock at 0.185 or silver at 28.125 keep the
    /// third decimal that a fixed two-digit rule would round away.
    public static func fractionLength(for market: Market) -> ClosedRange<Int> {
        switch market {
        case .crypto:
            // Spot pairs span many orders of magnitude; eight matches the text
            // export ceiling and still pads large coins to two places.
            return 2...8
        case .jp, .kr, .kq:
            // Equity prints are usually whole yen/won; indices can carry decimals.
            return 0...2
        case .us, .hk, .sh, .sz, .metal, .metalCN:
            // Two is the default tick; three covers HK penny bands, CN bonds /
            // some ETFs, and silver-style metal prints.
            return 2...3
        }
    }

    /// Upper bound of `fractionLength(for:)` — used by text exports and any
    /// caller that needs a single digit count rather than a display range.
    public static func fractionDigits(for market: Market) -> Int {
        fractionLength(for: market).upperBound
    }

    /// Formats a price, widening to the market's upper bound when the third
    /// (or further) digit carries information.
    public static func price(_ value: Double, market: Market? = nil) -> String {
        let length = market.map(fractionLength(for:)) ?? 2...3
        return rounded(value, fractionDigits: length.upperBound)
            .formatted(.number.precision(.fractionLength(length)).grouping(.never))
    }

    /// Magnitude snapped to the digits `price` will print. Pass this to
    /// `.numericText(value:)` so the transition tracks the same precision the
    /// string shows — including a third decimal when the market allows it.
    public static func animatablePrice(_ value: Double, market: Market? = nil) -> Double {
        let digits = market.map(fractionDigits(for:)) ?? 3
        return NSDecimalNumber(decimal: rounded(value, fractionDigits: digits)).doubleValue
    }

    /// Percent change: "+1.23%" / "-0.95%" / "0.00%"
    public static func percent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + value.formatted(.number.precision(.fractionLength(2))) + "%"
    }

    public static func percentMagnitude(_ value: Double) -> String {
        abs(value).formatted(.number.precision(.fractionLength(2))) + "%"
    }

    /// Price change (signed)
    public static func change(_ value: Double, market: Market? = nil) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + price(value, market: market)
    }

    public static func quantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
    }

    public static func money(_ value: Double, currencyCode: String?) -> String {
        // Sign before the symbol ("-$120.00", not "$-120.00") — negative
        // money shows up once short positions carry negative market value.
        (value < 0 ? "-" : "") + currencySymbol(currencyCode)
            + abs(value).formatted(.number.precision(.fractionLength(2)))
    }

    public static func signedMoney(_ value: Double, currencyCode: String?) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        return sign + money(abs(value), currencyCode: currencyCode)
    }

    public static func moneyMagnitude(_ value: Double, currencyCode: String?) -> String {
        money(abs(value), currencyCode: currencyCode)
    }

    /// Compact volume/turnover display using CJK scale units: wan (10^4) / yi (10^8)
    public static func compact(_ value: Double) -> String {
        if PulseLocalization.currentLanguageIdentifier == "en" {
            switch value {
            case 1e9...:
                return PulseLocalization.localizedString(
                    "number.compact.billion",
                    (value / 1e9).formatted(.number.precision(.fractionLength(2)))
                )
            case 1e6...:
                return PulseLocalization.localizedString(
                    "number.compact.million",
                    (value / 1e6).formatted(.number.precision(.fractionLength(1)))
                )
            case 1e3...:
                return PulseLocalization.localizedString(
                    "number.compact.thousand",
                    (value / 1e3).formatted(.number.precision(.fractionLength(0)))
                )
            default:
                return value.formatted(.number.precision(.fractionLength(0)))
            }
        }

        switch value {
        case 1e8...:
            return PulseLocalization.localizedString(
                "number.compact.hundredMillion",
                (value / 1e8).formatted(.number.precision(.fractionLength(2)))
            )
        case 1e4...:
            return PulseLocalization.localizedString(
                "number.compact.tenThousand",
                (value / 1e4).formatted(.number.precision(.fractionLength(1)))
            )
        default:
            return value.formatted(.number.precision(.fractionLength(0)))
        }
    }

    /// Up/down arrow for the menu bar
    public static func arrow(_ change: Double) -> String {
        change > 0 ? "▲" : (change < 0 ? "▼" : "–")
    }

    private static func rounded(_ value: Double, fractionDigits: Int) -> Decimal {
        var decimal = Decimal(value)
        var result = Decimal()
        NSDecimalRound(&result, &decimal, fractionDigits, .plain)
        return result
    }

    private static func currencySymbol(_ currencyCode: String?) -> String {
        switch currencyCode {
        case "CNY": "¥"
        case "HKD": "HK$"
        case "USD": "$"
        default: currencyCode.map { "\($0) " } ?? ""
        }
    }
}
