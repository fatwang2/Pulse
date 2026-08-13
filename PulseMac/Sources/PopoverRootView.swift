import AppKit
import SwiftUI
import PulseCore

enum PopoverRoute: Hashable {
    case list
    case detail(SymbolID)
    /// Position hub: summary, trade actions, and recent transactions.
    case position(SymbolID, PositionReturnRoute)
    /// Single-trade entry form; the side is fixed by the entry point.
    case trade(SymbolID, TradeSide, PositionReturnRoute)
    /// Full transaction log.
    case transactions(SymbolID, PositionReturnRoute)
    /// Quick set: overwrite quantity + average cost as one calibration entry.
    case calibrate(SymbolID, PositionReturnRoute)
    /// Full business summary, pushed from the detail page's excerpt.
    case profile(SymbolID)
    case settings
    case providerDetail(String)
    /// Import and export, kept off the settings list so it stays a short page.
    case dataSettings
}

enum TradeSide: Hashable {
    case buy
    case sell
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
    @Environment(\.pulseHost) private var host
    @State private var route: PopoverRoute = .list
    /// The standalone window animates this staged value alongside route motion.
    /// Owning the height explicitly keeps the lower-edge resize predictable while
    /// the retained watchlist preserves its title-bar safe area during exit.
    @State private var pinnedPresentedHeight: CGFloat?
    /// Search UI state lives at the root so pushing a detail page and coming back
    /// preserves the query, active state, and cached results.
    @State private var searchSession = SearchSession()

    private static let minHeight: CGFloat = 300
    private static let minListHeight: CGFloat = 220
    private static let maxHeight: CGFloat = 600
    private static let searchHeight: CGFloat = 480
    private static let listChromeHeight: CGFloat = 110
    /// The brand-and-actions row plus the stack spacing below it.
    private static let headerRowHeight: CGFloat = 33
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

    /// A child route whose symbol has been removed from the watchlist resolves
    /// back to the list; the stale `route` value is overwritten by the next push.
    private var displayRoute: PopoverRoute {
        switch route {
        case .position(let symbol, _), .trade(let symbol, _, _),
             .transactions(let symbol, _), .calibrate(let symbol, _):
            appState.watchlist.item(for: symbol) == nil ? .list : route
        default:
            route
        }
    }

    var body: some View {
        // ZStack lets the outgoing and incoming routes overlap during the push/pop
        // instead of stacking; one transaction drives both the swap and the height.
        // Each route is pinned to its own target height: while the container height
        // animates, the per-frame cost is clipping/compositing only — without the
        // pin, both live view trees would relayout on every frame of the resize,
        // which is what made pushes stutter.
        ZStack(alignment: .top) {
            // The list is the navigation root and stays mounted while children
            // sit on top of it, so its List scroll position survives the round
            // trip. Covered, it is disabled and nudged out along the leading
            // edge, tracing the same path its old removal transition drew.
            WatchlistView(route: $route, searchSession: $searchSession)
                .frame(height: height(for: .list))
                .opacity(displayRoute == .list ? 1 : 0)
                .offset(x: displayRoute == .list || reduceMotion ? 0 : -24)
                .disabled(displayRoute != .list)

            switch displayRoute {
            case .list:
                EmptyView()
            case .detail(let symbol):
                DetailView(symbol: symbol, route: $route)
                    .frame(height: height(for: displayRoute))
                    .transition(pushTransition)
            case .position(let symbol, let returnRoute):
                PositionHubView(symbol: symbol, returnRoute: returnRoute, route: $route)
                    .frame(height: height(for: displayRoute))
                    .transition(pushTransition)
            case .trade(let symbol, let side, let returnRoute):
                TradeEntryView(symbol: symbol, side: side, returnRoute: returnRoute, route: $route)
                    .frame(height: height(for: displayRoute))
                    .transition(pushTransition)
            case .transactions(let symbol, let returnRoute):
                TransactionListView(symbol: symbol, returnRoute: returnRoute, route: $route)
                    .frame(height: height(for: displayRoute))
                    .transition(pushTransition)
            case .calibrate(let symbol, let returnRoute):
                VStack(spacing: 0) {
                    // The panel's compact editor has Cancel at the bottom. In a window,
                    // every pushed page also needs the same visible navigation row as
                    // the rest of the position flow.
                    if host == .pinnedWindow {
                        PositionPageHeader(
                            symbol: symbol,
                            title: nil,
                            onBack: { route = .position(symbol, returnRoute) }
                        )
                    }
                    if let item = appState.watchlist.item(for: symbol) {
                        PositionEditorView(
                            item: item,
                            quote: appState.market.quote(for: symbol),
                            palette: appState.palette,
                            onCancel: { route = .position(symbol, returnRoute) },
                            onSave: { quantity, cost in
                                appState.watchlist.calibratePosition(symbol, quantity: quantity, averageCost: cost)
                                route = .position(symbol, returnRoute)
                            },
                            onClear: {
                                appState.watchlist.clearPosition(symbol)
                                route = .position(symbol, returnRoute)
                            }
                        )
                    }
                }
                .frame(height: height(for: displayRoute))
                .transition(pushTransition)
            case .profile(let symbol):
                ProfileView(symbol: symbol, route: $route)
                    .frame(height: height(for: displayRoute))
                    .transition(pushTransition)
            case .settings:
                SettingsView(route: $route)
                    .frame(height: height(for: displayRoute))
                    .transition(pushTransition)
            case .dataSettings:
                DataSettingsView(route: $route)
                    .frame(height: height(for: displayRoute))
                    .transition(pushTransition)
            case .providerDetail(let id):
                Group {
                    if id == LongbridgeProvider.providerID {
                        LongbridgeSetupView(route: $route)
                    } else if let descriptor = appState.providerDescriptors.first(where: { $0.id == id }) {
                        ProviderDetailView(descriptor: descriptor, route: $route)
                    }
                }
                .frame(height: height(for: displayRoute))
                .transition(pushTransition)
            }
        }
        .frame(width: 340, height: presentedHeight, alignment: .top)
        // Keep one title-bar skeleton mounted for the lifetime of the pinned
        // window. Route-specific views contribute actions, but an actionless page
        // no longer collapses the bar from 52pt to the empty 32pt window strip.
        .toolbar {
            if host == .pinnedWindow {
                ToolbarSpacer(.flexible)
            }
        }
        .background {
            EscapeBackMonitor {
                guard let previousRoute = previousRoute(for: displayRoute) else { return false }
                route = previousRoute
                return true
            }
        }
        .clipped()
        .animation(.snappy(duration: 0.28), value: displayRoute)
        .animation(.snappy(duration: 0.28), value: searchSession.isActive)
        // The pinned window owns a staged height value below; the panel keeps
        // its existing system-anchored resize animation.
        .animation(host == .menuBar ? .snappy(duration: 0.28) : nil, value: height(for: displayRoute))
        // Live subscriptions run only while a host is on screen
        .onAppear {
            if host == .pinnedWindow {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    pinnedPresentedHeight = height(for: displayRoute)
                }
            }
            appState.setHostVisible(host, true)
            // Product analytics counts panel opens only; the pinned window stays up for
            // hours at a time and would otherwise read as a single enormous session.
            if host == .menuBar { PulseTelemetry.signal(.popoverOpened) }
        }
        .onDisappear {
            appState.setHostVisible(host, false)
            // Closing the host ends the current search presentation.
            // Keep the result cache warm, but reopen on the normal watchlist.
            searchSession.text = ""
            searchSession.isActive = false
            // SwiftUI retains a closed Window scene and its @State. Without an
            // explicit reset, re-pinning can resurrect the detail/settings route
            // that happened to be open when the user closed the window.
            if host == .pinnedWindow {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    route = .list
                    pinnedPresentedHeight = height(for: .list)
                }
            }
        }
        .onChange(of: height(for: displayRoute)) { _, targetHeight in
            guard host == .pinnedWindow else { return }
            // Resize in the same 280ms window as the route push. The retained
            // list keeps its toolbar safe area, so its exit remains horizontal
            // while the lower window edge moves.
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                pinnedPresentedHeight = targetHeight
            }
        }
        .onChange(of: appState.watchlist.symbols) { _, _ in
            appState.watchlistSymbolsChanged()
        }
        .onChange(of: appState.watchlist.groups.map(\.id)) { _, _ in
            appState.watchlistGroupsChanged()
        }
    }

    /// The pinned window animates this value alongside the page transition.
    /// Menu-bar panels keep their existing live size behavior.
    private var presentedHeight: CGFloat {
        host == .pinnedWindow
            ? (pinnedPresentedHeight ?? height(for: displayRoute))
            : height(for: displayRoute)
    }

    /// The pinned window lifts the watchlist's brand-and-actions row into its title bar,
    /// so the list page there is exactly that row shorter.
    private var listChromeHeight: CGFloat {
        host == .pinnedWindow ? Self.listChromeHeight - Self.headerRowHeight : Self.listChromeHeight
    }

    private func previousRoute(for route: PopoverRoute) -> PopoverRoute? {
        switch route {
        case .list:
            nil
        case .detail:
            .list
        case .position(_, let returnRoute):
            returnRoute.popoverRoute
        case .trade(let symbol, _, let returnRoute),
             .transactions(let symbol, let returnRoute),
             .calibrate(let symbol, let returnRoute):
            .position(symbol, returnRoute)
        case .profile(let symbol):
            .detail(symbol)
        case .settings:
            .list
        case .providerDetail, .dataSettings:
            .settings
        }
    }

    /// The list page height adapts to the watchlist size (chrome, row height, bottom bar, and padding),
    /// clamped between the min and max
    private func height(for route: PopoverRoute) -> CGFloat {
        switch route {
        case .list:
            // The search panel needs room for results/recents regardless of list size.
            if searchSession.isActive { return Self.searchHeight }
            let content = listChromeHeight + CGFloat(appState.watchlist.items.count) * Self.listRowHeight
            let minimum = appState.watchlist.items.isEmpty ? Self.minHeight : Self.minListHeight
            return min(max(content, minimum), Self.maxHeight)
        case .detail:
            return 560
        case .profile:
            return 440
        case .position(let symbol, _):
            // Summary + trade actions + recent trades once anything has been
            // traded; only a symbol with no history at all gets the compact
            // pitch for recording a first trade.
            guard let item = appState.watchlist.item(for: symbol) else { return 360 }
            if item.hasPosition { return 420 }
            return item.transactions.isEmpty ? 300 : 380
        case .trade:
            return 330
        case .transactions:
            return 500
        case .calibrate:
            return 370
        case .settings:
            return 540
        case .providerDetail, .dataSettings:
            // Same height as the settings page it navigates from, so the popover
            // doesn't shrink on push and the taller pages don't need scrolling.
            return 540
        }
    }
}

/// `MenuBarExtra` closes its window before SwiftUI's exit-command handlers
/// receive Escape. Monitor the host window directly so child routes can consume
/// Escape as back, while events in nested popovers and the root list retain
/// their normal system behavior.
private struct EscapeBackMonitor: NSViewRepresentable {
    let onEscape: () -> Bool

    func makeNSView(context: Context) -> EscapeBackMonitorView {
        let view = EscapeBackMonitorView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ view: EscapeBackMonitorView, context: Context) {
        view.onEscape = onEscape
    }

    static func dismantleNSView(_ view: EscapeBackMonitorView, coordinator: ()) {
        view.removeMonitor()
    }
}

@MainActor
private final class EscapeBackMonitorView: NSView {
    var onEscape: () -> Bool = { false }
    private var monitor: Any?
    private var isConsumingEscape = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard let hostWindow = window else { return }

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp]
        ) { [weak self, weak hostWindow] event in
            guard event.keyCode == 53, event.window === hostWindow, let self else {
                return event
            }

            if event.type == .keyUp {
                guard self.isConsumingEscape else { return event }
                self.isConsumingEscape = false
                return nil
            }
            if event.isARepeat {
                return self.isConsumingEscape ? nil : event
            }
            guard self.onEscape() else { return event }
            self.isConsumingEscape = true
            return nil
        }
    }

    func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        isConsumingEscape = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
