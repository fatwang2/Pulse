import SwiftUI

/// Up/down color palette. Defaults to red-up/green-down (A-share convention); can switch to green-up/red-down (US convention).
public struct ChangePalette: Sendable {
    public var redUp: Bool

    public init(redUp: Bool = true) {
        self.redUp = redUp
    }

    public static let up = Color(red: 0.94, green: 0.26, blue: 0.27)      // red
    public static let down = Color(red: 0.04, green: 0.66, blue: 0.35)    // green

    public func color(for change: Double) -> Color {
        if change > 0 { return redUp ? Self.up : Self.down }
        if change < 0 { return redUp ? Self.down : Self.up }
        return .secondary
    }

    public func color(isUp: Bool) -> Color {
        isUp ? color(for: 1) : color(for: -1)
    }
}
