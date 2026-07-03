import SwiftUI
import PulseCore

enum PopoverRoute: Hashable {
    case list
    case detail(SymbolID)
    case settings
}

struct PopoverRootView: View {
    @Environment(AppState.self) private var appState
    @State private var route: PopoverRoute = .list

    private static let minHeight: CGFloat = 300
    private static let maxHeight: CGFloat = 600

    var body: some View {
        Group {
            switch route {
            case .list:
                WatchlistView(route: $route)
            case .detail(let symbol):
                DetailView(symbol: symbol, route: $route)
            case .settings:
                SettingsView(route: $route)
            }
        }
        .frame(width: 340, height: height)
    }

    /// The list page height adapts to the watchlist size (chrome ~78 + row height ~43 + bottom bar ~38 + bottom padding 28),
    /// clamped between the min and max
    private var height: CGFloat {
        switch route {
        case .list:
            let content = 158 + CGFloat(appState.watchlist.items.count) * 43
            return min(max(content, Self.minHeight), Self.maxHeight)
        case .detail:
            return 480
        case .settings:
            return 540
        }
    }
}
