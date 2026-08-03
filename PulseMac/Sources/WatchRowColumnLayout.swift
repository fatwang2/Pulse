import AppKit

enum WatchRowPresentation {
    case popover
    case share
}

/// Shared content-aware column measurement for the live watchlist and exported watchlist image.
/// Each surface uses its own typography, but both follow the same rule: the widest required
/// title/metric width becomes the common column width for every row.
enum WatchRowColumnLayout {
    static func titleWidth(
        name: String,
        symbolCode: String,
        marketName: String,
        presentation: WatchRowPresentation,
        trailingAccessoryWidth: CGFloat = 0
    ) -> CGFloat {
        let metrics = Metrics(presentation)
        let nameWidth = measure(name, font: metrics.nameFont) + trailingAccessoryWidth
        let badgeWidth = measure(marketName, font: metrics.badgeFont) + 7
        let symbolWidth = badgeWidth + metrics.badgeGap + measure(symbolCode, font: metrics.symbolFont)
        return min(max(max(nameWidth, symbolWidth), metrics.minimumTitleWidth), metrics.maximumTitleWidth)
    }

    static func nameIsTruncated(
        _ name: String,
        availableWidth: CGFloat,
        presentation: WatchRowPresentation
    ) -> Bool {
        let metrics = Metrics(presentation)
        return measure(name, font: metrics.nameFont) > availableWidth
    }

    /// Share rows stack the session label above the price, so the column fits the wider of the two.
    static func sharePriceWidth(priceText: String, sessionLabel: String?) -> CGFloat {
        let metrics = Metrics(.share)
        let priceWidth = measure(priceText, font: metrics.priceFont)
        let sessionWidth = sessionLabel.map { measure($0, font: metrics.sessionFont) } ?? 0
        return max(max(priceWidth, sessionWidth), 40)
    }

    /// Share rows show the metric inside a fixed-width pill; the widest metric wins, floored at 86pt.
    static func sharePillWidth(metricText: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .bold)
        return max(measure(metricText, font: font) + 24, 86)
    }

    static func metricWidth(
        priceText: String,
        metricText: String,
        sessionLabel: String?,
        presentation: WatchRowPresentation
    ) -> CGFloat {
        let metrics = Metrics(presentation)
        var priceWidth = measure(priceText, font: metrics.priceFont)
        if let sessionLabel {
            priceWidth += measure(sessionLabel, font: metrics.sessionFont) + 4
        }
        let valueWidth = measure(metricText, font: metrics.metricFont)
        return min(max(max(priceWidth, valueWidth), metrics.minimumMetricWidth), metrics.maximumMetricWidth)
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private struct Metrics {
        let nameFont: NSFont
        let badgeFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let symbolFont: NSFont
        let priceFont: NSFont
        let metricFont: NSFont
        let sessionFont = NSFont.systemFont(ofSize: 8.5, weight: .medium)
        let badgeGap: CGFloat
        let minimumTitleWidth: CGFloat
        let maximumTitleWidth: CGFloat
        let minimumMetricWidth: CGFloat
        let maximumMetricWidth: CGFloat

        init(_ presentation: WatchRowPresentation) {
            switch presentation {
            case .popover:
                nameFont = .systemFont(ofSize: 12.5, weight: .medium)
                symbolFont = .monospacedSystemFont(ofSize: 10, weight: .regular)
                priceFont = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
                metricFont = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
                badgeGap = 4
                minimumTitleWidth = 48
                maximumTitleWidth = 116
                minimumMetricWidth = 48
                maximumMetricWidth = 104
            case .share:
                nameFont = .systemFont(ofSize: 14.5, weight: .medium)
                symbolFont = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
                priceFont = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
                metricFont = .monospacedDigitSystemFont(ofSize: 13.5, weight: .bold)
                badgeGap = 6
                minimumTitleWidth = 58
                maximumTitleWidth = 240
                minimumMetricWidth = 58
                maximumMetricWidth = 132
            }
        }
    }
}
