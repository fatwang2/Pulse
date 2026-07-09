import Foundation

/// Market identifier. Shanghai and Shenzhen are modeled separately (data sources use different symbol formats); the UI layer may merge them into a single "China A-shares" presentation.
public enum Market: String, Codable, Sendable, CaseIterable, Hashable {
    case us
    case hk
    case sh
    case sz
    case crypto

    public var displayName: String {
        switch self {
        case .us: PulseLocalization.localizedString("market.us")
        case .hk: PulseLocalization.localizedString("market.hk")
        case .sh: PulseLocalization.localizedString("market.sh")
        case .sz: PulseLocalization.localizedString("market.sz")
        case .crypto: PulseLocalization.localizedString("market.crypto")
        }
    }

    public var currencyCode: String {
        switch self {
        case .us: "USD"
        case .hk: "HKD"
        case .sh, .sz: "CNY"
        case .crypto: "USD"
        }
    }

    public var timeZone: TimeZone {
        switch self {
        case .us: TimeZone(identifier: "America/New_York")!
        case .hk: TimeZone(identifier: "Asia/Hong_Kong")!
        case .sh, .sz: TimeZone(identifier: "Asia/Shanghai")!
        case .crypto: TimeZone(identifier: "UTC")!
        }
    }

    public var timeZoneDisplayName: String {
        switch self {
        case .us: PulseLocalization.localizedString("market.timeZone.us")
        case .hk: PulseLocalization.localizedString("market.timeZone.hk")
        case .sh, .sz: PulseLocalization.localizedString("market.timeZone.cn")
        case .crypto: PulseLocalization.localizedString("market.timeZone.utc")
        }
    }

    public var isChinaA: Bool { self == .sh || self == .sz }
}
