import SwiftUI
import PulseCore
import PulseUI

enum IOSRoute: Hashable {
    case detail(SymbolID)
    case profile(SymbolID)
}

/// Home: watchlist groups as glass chips over a plain quote list. Navigation,
/// search, and display settings live in the toolbar, which iOS 26 renders as
/// floating Liquid Glass on its own.
struct WatchlistScreen: View {
    @Environment(IOSAppState.self) private var appState

    @State private var showsSearch = false
    @State private var showsSettings = false
    @State private var path: [IOSRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if appState.watchlist.isEmpty {
                    emptyState
                } else {
                    quoteList
                }
            }
            .navigationTitle("Pulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label(
                            PulseLocalization.localizedString("settings.title"),
                            systemImage: "slider.horizontal.3"
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSearch = true
                    } label: {
                        Label(
                            PulseLocalization.localizedString("action.search"),
                            systemImage: "magnifyingglass"
                        )
                    }
                }
            }
            .navigationDestination(for: IOSRoute.self) { route in
                switch route {
                case .detail(let symbol):
                    DetailScreen(symbol: symbol)
                case .profile(let symbol):
                    ProfileScreen(symbol: symbol)
                }
            }
        }
        .sheet(isPresented: $showsSearch) {
            SearchSheet { symbol in
                showsSearch = false
                path.append(.detail(symbol))
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet()
        }
        // ASWebAuthenticationSession delivers its callback directly; this covers
        // an authorize page that escaped to external Safari.
        .onOpenURL { url in
            appState.handleOAuthCallback(url)
        }
        .onAppear { appState.setWatchlistVisible(true) }
        .onDisappear { appState.setWatchlistVisible(false) }
    }

    // MARK: - List

    private var quoteList: some View {
        List {
            if appState.watchlist.groups.count > 1 {
                groupChips
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(appState.watchlist.items) { item in
                Button {
                    path.append(.detail(item.symbol))
                } label: {
                    QuoteRow(item: item)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: removeItems)
        }
        .listStyle(.plain)
        .animation(.default, value: appState.watchlist.items.map(\.symbol))
    }

    private func removeItems(at offsets: IndexSet) {
        let items = appState.watchlist.items
        for offset in offsets {
            guard items.indices.contains(offset) else { continue }
            appState.watchlist.remove(items[offset].symbol)
        }
        appState.watchlistSymbolsChanged()
    }

    // MARK: - Groups

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.watchlist.groups) { group in
                    groupChip(group)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func groupChip(_ group: WatchlistGroup) -> some View {
        let isSelected = appState.watchlist.selectedGroup?.id == group.id
        return Button {
            appState.watchlist.selectGroup(group.id)
            appState.watchlistSymbolsChanged()
        } label: {
            Text(group.name)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 4)
        }
        .buttonStyle(.glass)
        .tint(isSelected ? .accentColor : .secondary)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                PulseLocalization.localizedString("watchlist.empty.title"),
                systemImage: "chart.line.uptrend.xyaxis"
            )
        } description: {
            Text(PulseLocalization.localizedString("empty.watchlist"))
        } actions: {
            Button {
                showsSearch = true
            } label: {
                Label(
                    PulseLocalization.localizedString("action.addSymbol"),
                    systemImage: "plus"
                )
            }
            .buttonStyle(.glassProminent)
        }
    }

}
