import SwiftUI
import PulseCore

/// Market badge: small US/HK/SH/SZ tag
public struct MarketBadge: View {
    let market: Market

    public init(market: Market) {
        self.market = market
    }

    private var color: Color {
        switch market {
        case .us: .blue
        case .hk: .indigo
        case .sh: .orange
        case .sz: .teal
        }
    }

    public var body: some View {
        Text(market.displayName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 3))
    }
}
