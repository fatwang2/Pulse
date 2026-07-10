import SwiftUI
import PulseCore

enum PopoverRoute: Hashable {
    case list
    case detail(SymbolID)
    case position(SymbolID, PositionReturnRoute)
    case settings
}

enum PositionReturnRoute: Hashable {
    case list
    case detail(SymbolID)

    var popoverRoute: PopoverRoute {
        switch self {
        case .list:
            .list
        case .detail(let symbol):
            .detail(symbol)
        }
    }
}

struct PopoverRootView: View {
    @Environment(AppState.self) private var appState
    @State private var route: PopoverRoute = .list

    private static let minHeight: CGFloat = 300
    private static let minListHeight: CGFloat = 220
    private static let maxHeight: CGFloat = 600
    private static let listChromeHeight: CGFloat = 112
    private static let listRowHeight: CGFloat = 48

    var body: some View {
        Group {
            switch route {
            case .list:
                WatchlistView(route: $route)
            case .detail(let symbol):
                DetailView(symbol: symbol, route: $route)
            case .position(let symbol, let returnRoute):
                if let item = appState.watchlist.item(for: symbol) {
                    PositionEditorView(
                        item: item,
                        quote: appState.market.quote(for: symbol),
                        palette: appState.palette,
                        onCancel: { route = returnRoute.popoverRoute },
                        onSave: { lots in
                            appState.watchlist.updateLots(symbol, lots: lots)
                            route = returnRoute.popoverRoute
                        },
                        onClear: {
                            appState.watchlist.clearPosition(symbol)
                            route = returnRoute.popoverRoute
                        }
                    )
                } else {
                    WatchlistView(route: $route)
                }
            case .settings:
                SettingsView(route: $route)
            }
        }
        .frame(width: 340, height: height)
    }

    /// The list page height adapts to the watchlist size (chrome, row height, bottom bar, and padding),
    /// clamped between the min and max
    private var height: CGFloat {
        switch route {
        case .list:
            let content = Self.listChromeHeight + CGFloat(appState.watchlist.items.count) * Self.listRowHeight
            let minimum = appState.watchlist.items.isEmpty ? Self.minHeight : Self.minListHeight
            return min(max(content, minimum), Self.maxHeight)
        case .detail:
            return 560
        case .position:
            return 360
        case .settings:
            return 540
        }
    }
}
