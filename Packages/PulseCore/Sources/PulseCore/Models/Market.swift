import Foundation

/// Market identifier. Shanghai and Shenzhen are modeled separately (data sources use different symbol formats); the UI layer may merge them into a single "China A-shares" presentation.
public enum Market: String, Codable, Sendable, CaseIterable, Hashable {
    case us
    case hk
    case sh
    case sz

    public var displayName: String {
        switch self {
        case .us: "美股"
        case .hk: "港股"
        case .sh: "沪"
        case .sz: "深"
        }
    }

    public var currencyCode: String {
        switch self {
        case .us: "USD"
        case .hk: "HKD"
        case .sh, .sz: "CNY"
        }
    }

    public var timeZone: TimeZone {
        switch self {
        case .us: TimeZone(identifier: "America/New_York")!
        case .hk: TimeZone(identifier: "Asia/Hong_Kong")!
        case .sh, .sz: TimeZone(identifier: "Asia/Shanghai")!
        }
    }

    public var isChinaA: Bool { self == .sh || self == .sz }
}
