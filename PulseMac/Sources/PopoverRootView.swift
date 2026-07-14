import SwiftUI
import PulseCore

enum PopoverRoute: Hashable {
    case list
    case detail(SymbolID)
    case position(SymbolID, PositionReturnRoute)
    case settings
    case providerDetail(String)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var route: PopoverRoute = .list

    private static let minHeight: CGFloat = 300
    private static let minListHeight: CGFloat = 220
    private static let maxHeight: CGFloat = 600
    private static let listChromeHeight: CGFloat = 112
    private static let listRowHeight: CGFloat = 48

    /// Children push in from the trailing edge and pop back out the same way
    /// (spatial consistency: a screen exits along the path it entered).
    private var pushTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
    }

    /// The list is the navigation root: it always lives to the left of its children.
    private var rootTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    var body: some View {
        // ZStack lets the outgoing and incoming routes overlap during the push/pop
        // instead of stacking; one transaction drives both the swap and the height.
        // Each route is pinned to its own target height: while the container height
        // animates, the per-frame cost is clipping/compositing only — without the
        // pin, both live view trees would relayout on every frame of the resize,
        // which is what made pushes stutter.
        ZStack(alignment: .top) {
            switch route {
            case .list:
                WatchlistView(route: $route)
                    .frame(height: height(for: route))
                    .transition(rootTransition)
            case .detail(let symbol):
                DetailView(symbol: symbol, route: $route)
                    .frame(height: height(for: route))
                    .transition(pushTransition)
            case .position(let symbol, let returnRoute):
                Group {
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
                }
                .frame(height: height(for: route))
                .transition(pushTransition)
            case .settings:
                SettingsView(route: $route)
                    .frame(height: height(for: route))
                    .transition(pushTransition)
            case .providerDetail(let id):
                Group {
                    if id == LongbridgeProvider.providerID {
                        LongbridgeSetupView(route: $route)
                    } else if let descriptor = appState.providerDescriptors.first(where: { $0.id == id }) {
                        ProviderDetailView(descriptor: descriptor, route: $route)
                    }
                }
                .frame(height: height(for: route))
                .transition(pushTransition)
            }
        }
        .frame(width: 340, height: height(for: route), alignment: .top)
        .clipped()
        .animation(.snappy(duration: 0.28), value: route)
        .animation(.snappy(duration: 0.28), value: height(for: route))
        // Live subscriptions run only while the popover is on screen
        .onAppear { appState.setPopoverVisible(true) }
        .onDisappear { appState.setPopoverVisible(false) }
        .onChange(of: appState.watchlist.symbols) { _, _ in
            appState.watchlistSymbolsChanged()
        }
    }

    /// The list page height adapts to the watchlist size (chrome, row height, bottom bar, and padding),
    /// clamped between the min and max
    private func height(for route: PopoverRoute) -> CGFloat {
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
        case .providerDetail:
            // Same height as the settings page it navigates from, so the popover
            // doesn't shrink on push and the taller pages don't need scrolling.
            return 540
        }
    }
}
