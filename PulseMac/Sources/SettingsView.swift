import SwiftUI
import PulseCore

/// One data source in the settings list: a plain navigation row (name, summary, state, ›).
/// The enable switch and any connection flow live on the source's own detail page, so every
/// provider — connectable or not — shares one row shape and one behavior.
struct ProviderRow: View {
    @Environment(AppState.self) private var appState
    let descriptor: ProviderDescriptor
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.name)
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(PulseLocalization.localizedString(statusKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private var isConnectable: Bool { !descriptor.credentials.isEmpty }

    private var statusKey: String {
        if descriptor.id == LongbridgeProvider.providerID {
            guard appState.longbridgeConfigured else { return "provider.status.notConnected" }
            guard appState.isProviderEnabled(descriptor.id) else { return "provider.status.off" }
            return switch appState.longbridgeConnectionStatus {
            case .disconnected: "provider.status.authorized"
            case .connecting: "provider.status.connecting"
            case .reconnecting: "provider.status.reconnecting"
            case .connected: "provider.status.connected"
            case .failed: "provider.status.fallback"
            }
        }
        if isConnectable && !appState.longbridgeConfigured { return "provider.status.notConnected" }
        guard appState.isProviderEnabled(descriptor.id) else { return "provider.status.off" }
        return "provider.status.on"
    }

    private var summary: String {
        // The list only previews market coverage; capabilities and freshness live on
        // the detail page. Derive this from the descriptor so the two stay in sync.
        let separator = PulseLocalization.localizedString("provider.summary.separator")
        return Market.allCases
            .filter { descriptor.markets.contains($0) }
            .map(\.displayName)
            .joined(separator: separator)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var route: PopoverRoute
    @StateObject private var softwareUpdate = SoftwareUpdateController.shared

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section {
                Toggle(PulseLocalization.localizedString("settings.menuBar.showQuote"), isOn: $settings.showPriceInMenuBar)
                if settings.showPriceInMenuBar {
                    Picker(PulseLocalization.localizedString("settings.menuBar.displayMode"), selection: $settings.menuBarMode) {
                        Text(MenuBarMode.single.displayName).tag(MenuBarMode.single)
                        Text(MenuBarMode.rotate.displayName).tag(MenuBarMode.rotate)
                    }
                    .transition(contextualRowTransition)
                    if settings.menuBarMode == .single {
                        Picker(PulseLocalization.localizedString("settings.menuBar.fixedSymbol"), selection: $settings.primarySymbol) {
                            Text(PulseLocalization.localizedString("settings.menuBar.firstWatchlistItem")).tag(SymbolID?.none)
                            ForEach(appState.watchlist.items) { item in
                                Text(item.displayName).tag(SymbolID?.some(item.symbol))
                            }
                        }
                        .transition(contextualRowTransition)
                    }
                    if settings.menuBarMode == .rotate {
                        Picker(PulseLocalization.localizedString("settings.menuBar.rotateInterval"), selection: $settings.rotateInterval) {
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

            Section(PulseLocalization.localizedString("settings.section.market")) {
                // Refresh cadence moved to each data source's detail page — sources have
                // very different politeness budgets, so a global interval stopped making sense.
                Picker(PulseLocalization.localizedString("settings.market.colorRule"), selection: $settings.redUp) {
                    Text(PulseLocalization.localizedString("settings.market.redUp")).tag(true)
                    Text(PulseLocalization.localizedString("settings.market.greenUp")).tag(false)
                }
            }

            Section {
                ForEach(appState.providerDescriptors, id: \.id) { descriptor in
                    ProviderRow(descriptor: descriptor) {
                        route = .providerDetail(descriptor.id)
                    }
                }
            } header: {
                Text(PulseLocalization.localizedString("settings.section.providers"))
            } footer: {
                if appState.providerDescriptors.allSatisfy({ !appState.isProviderEnabled($0.id) }) {
                    Text(PulseLocalization.localizedString("settings.providers.allDisabled"))
                        .foregroundStyle(.orange)
                } else {
                    Text(PulseLocalization.localizedString("settings.providers.help"))
                }
            }

            Section {
                Picker(PulseLocalization.localizedString("settings.general.language"), selection: $settings.languagePreference) {
                    ForEach(PulseLanguagePreference.allCases, id: \.self) { preference in
                        Text(preference.localizedDisplayName).tag(preference)
                    }
                }
                Toggle(PulseLocalization.localizedString("settings.general.launchAtLogin"), isOn: $settings.launchAtLogin)
                Toggle(
                    PulseLocalization.localizedString("settings.general.anonymousAnalytics"),
                    isOn: $settings.shareAnonymousUsageData
                )
            } header: {
                Text(PulseLocalization.localizedString("settings.section.general"))
            } footer: {
                Text(PulseLocalization.localizedString("settings.general.anonymousAnalyticsHelp"))
            }

            Section {
                LabeledContent(
                    PulseLocalization.localizedString("settings.updates.currentVersion"),
                    value: "\(softwareUpdate.currentVersion) (\(softwareUpdate.currentBuild))"
                )
                Button(PulseLocalization.localizedString("settings.updates.check")) {
                    softwareUpdate.checkForUpdates()
                }
                .disabled(!softwareUpdate.isConfigured)
            } header: {
                Text(PulseLocalization.localizedString("settings.section.updates"))
            }
        }
        .animation(contextualRowAnimation, value: settings.showPriceInMenuBar)
        .animation(contextualRowAnimation, value: settings.menuBarMode)
        .formStyle(.grouped)
        .controlSize(.small)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .onAppear { PulseTelemetry.signal(.settingsOpened) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.back")) {
                route = .list
            }
            Text(PulseLocalization.localizedString("settings.title"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

}
