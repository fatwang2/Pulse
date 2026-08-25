import SwiftUI
import PulseCore

/// Settings → Appearance: menu-bar display and market presentation.
/// Kept one level down so the settings root stays a short index of destinations.
struct AppearanceSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulseHost) private var host
    @Binding var route: PopoverRoute

    var body: some View {
        @Bindable var settings = appState.settings

        VStack(spacing: 0) {
            header

            Form {
                Section {
                    Toggle(
                        PulseLocalization.localizedString("settings.menuBar.showQuote"),
                        isOn: $settings.showPriceInMenuBar
                    )
                    if settings.showPriceInMenuBar {
                        Picker(
                            PulseLocalization.localizedString("settings.menuBar.displayMode"),
                            selection: $settings.menuBarMode
                        ) {
                            Text(MenuBarMode.single.displayName).tag(MenuBarMode.single)
                            Text(MenuBarMode.rotate.displayName).tag(MenuBarMode.rotate)
                        }
                        .transition(contextualRowTransition)
                        if settings.menuBarMode == .single {
                            Picker(
                                PulseLocalization.localizedString("settings.menuBar.fixedSymbol"),
                                selection: $settings.primarySymbol
                            ) {
                                Text(PulseLocalization.localizedString("settings.menuBar.firstWatchlistItem"))
                                    .tag(SymbolID?.none)
                                ForEach(appState.watchlist.allItems) { item in
                                    Text(item.resolvedDisplayName).tag(SymbolID?.some(item.symbol))
                                }
                            }
                            .transition(contextualRowTransition)
                        }
                        if settings.menuBarMode == .rotate {
                            if appState.watchlist.groups.count > 1 {
                                Picker(
                                    PulseLocalization.localizedString("settings.menuBar.rotateGroup"),
                                    selection: menuBarRotationGroupBinding
                                ) {
                                    ForEach(appState.watchlist.groups) { group in
                                        Text(group.name).tag(Optional(group.id))
                                    }
                                }
                                .transition(contextualRowTransition)
                            }
                            Picker(
                                PulseLocalization.localizedString("settings.menuBar.rotateInterval"),
                                selection: $settings.rotateInterval
                            ) {
                                Text(PulseLocalization.localizedString("duration.seconds", 3)).tag(TimeInterval(3))
                                Text(PulseLocalization.localizedString("duration.seconds", 6)).tag(TimeInterval(6))
                                Text(PulseLocalization.localizedString("duration.seconds", 10)).tag(TimeInterval(10))
                            }
                            .transition(contextualRowTransition)
                        }
                    }
                } header: {
                    Text(PulseLocalization.localizedString("settings.section.menuBar"))
                } footer: {
                    if !settings.showPriceInMenuBar {
                        Text(PulseLocalization.localizedString("settings.menuBar.iconOnlyHelp"))
                            .transition(.opacity)
                    }
                }

                Section {
                    Picker(
                        PulseLocalization.localizedString("settings.market.colorRule"),
                        selection: $settings.redUp
                    ) {
                        Text(PulseLocalization.localizedString("settings.market.redUp")).tag(true)
                        Text(PulseLocalization.localizedString("settings.market.greenUp")).tag(false)
                    }
                    Toggle(
                        PulseLocalization.localizedString("settings.market.usExtendedHours"),
                        isOn: $settings.showsUSExtendedHours
                    )
                    Toggle(
                        PulseLocalization.localizedString("settings.market.prioritizeOpenMarkets"),
                        isOn: $settings.prioritizeOpenMarkets
                    )
                } header: {
                    Text(PulseLocalization.localizedString("settings.section.market"))
                } footer: {
                    Text(PulseLocalization.localizedString("settings.market.prioritizeOpenMarketsHelp"))
                }
            }
            .animation(contextualRowAnimation, value: settings.showPriceInMenuBar)
            .animation(contextualRowAnimation, value: settings.menuBarMode)
            .formStyle(.grouped)
            .controlSize(.small)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.backHelp")) {
                route = .settings
            }
            Text(PulseLocalization.localizedString("settings.section.appearance"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, host == .pinnedWindow ? 2 : 8)
        .padding(.bottom, 8)
    }

    private var contextualRowTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    private var contextualRowAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.15)
            : .snappy(duration: 0.22)
    }

    private var menuBarRotationGroupBinding: Binding<UUID?> {
        Binding(
            get: { appState.menuBarRotationGroupID },
            set: { id in
                guard let id else { return }
                appState.setMenuBarRotationGroup(id)
            }
        )
    }
}
