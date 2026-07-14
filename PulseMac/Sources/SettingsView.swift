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
                }
                Spacer()
                Text(PulseLocalization.localizedString(statusKey))
                    .font(.caption)
                    .foregroundStyle(statusIsPositive ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isConnectable: Bool { !descriptor.credentials.isEmpty }

    private var statusKey: String {
        guard appState.isProviderEnabled(descriptor.id) else { return "provider.status.off" }
        guard isConnectable else { return "provider.status.on" }
        return appState.longbridgeConfigured ? "provider.status.connected" : "provider.status.notConnected"
    }

    private var statusIsPositive: Bool {
        isConnectable && appState.isProviderEnabled(descriptor.id) && appState.longbridgeConfigured
    }

    private var summary: String {
        let summaryKey = "provider.\(descriptor.id).summary"
        let localizedSummary = PulseLocalization.localizedString(summaryKey)
        if localizedSummary != summaryKey {
            return localizedSummary
        }

        let markets = Market.allCases
            .filter { descriptor.markets.contains($0) }
            .map(\.displayName)
            .joined(separator: ", ")
        var capabilities: [String] = []
        if descriptor.capabilities.contains(.quotes) {
            capabilities.append(PulseLocalization.localizedString("provider.capability.quotes"))
        }
        if descriptor.capabilities.contains(.candles) {
            capabilities.append(PulseLocalization.localizedString("provider.capability.candles"))
        }
        if descriptor.capabilities.contains(.search) {
            capabilities.append(PulseLocalization.localizedString("provider.capability.search"))
        }
        if descriptor.capabilities.contains(.streaming) {
            capabilities.append(PulseLocalization.localizedString("provider.capability.streaming"))
        }
        let realtime = switch descriptor.delayClass {
        case .realtime: PulseLocalization.localizedString("provider.delay.realtime")
        case .partiallyRealtime: PulseLocalization.localizedString("provider.delay.partial")
        case .delayed: PulseLocalization.localizedString("provider.delay.delayed")
        }
        return "\(markets) · \(capabilities.joined(separator: ", ")) · \(realtime)"
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
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
                    if settings.menuBarMode == .single {
                        Picker(PulseLocalization.localizedString("settings.menuBar.fixedSymbol"), selection: $settings.primarySymbol) {
                            Text(PulseLocalization.localizedString("settings.menuBar.firstWatchlistItem")).tag(SymbolID?.none)
                            ForEach(appState.watchlist.items) { item in
                                Text(item.displayName).tag(SymbolID?.some(item.symbol))
                            }
                        }
                    }
                    if settings.menuBarMode == .rotate {
                        Picker(PulseLocalization.localizedString("settings.menuBar.rotateInterval"), selection: $settings.rotateInterval) {
                            Text(PulseLocalization.localizedString("duration.seconds", 3)).tag(TimeInterval(3))
                            Text(PulseLocalization.localizedString("duration.seconds", 6)).tag(TimeInterval(6))
                            Text(PulseLocalization.localizedString("duration.seconds", 10)).tag(TimeInterval(10))
                        }
                    }
                }
            } header: {
                Text(PulseLocalization.localizedString("settings.section.menuBar"))
            } footer: {
                if !settings.showPriceInMenuBar {
                    Text(PulseLocalization.localizedString("settings.menuBar.iconOnlyHelp"))
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

            Section(PulseLocalization.localizedString("settings.section.general")) {
                Picker(PulseLocalization.localizedString("settings.general.language"), selection: $settings.languagePreference) {
                    ForEach(PulseLanguagePreference.allCases, id: \.self) { preference in
                        Text(preference.localizedDisplayName).tag(preference)
                    }
                }
                Toggle(PulseLocalization.localizedString("settings.general.launchAtLogin"), isOn: $settings.launchAtLogin)
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
        .formStyle(.grouped)
        .controlSize(.small)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaInset(edge: .top, spacing: 0) { header }
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

}
