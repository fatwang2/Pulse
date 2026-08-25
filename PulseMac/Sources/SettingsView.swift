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

    private var statusKey: String {
        // One question per row: does this source participate in quotes? The
        // credential story lives on the detail page, where an unverified account
        // source keeps its enable switch locked — so "not enabled" covers it.
        appState.isProviderConfigured(descriptor.id) && appState.isProviderEnabled(descriptor.id)
            ? "provider.status.on"
            : "provider.status.off"
    }

    private var summary: String {
        // The list only previews market coverage; capabilities and freshness live on
        // the detail page. Derive this from the descriptor so the two stay in sync.
        let separator = PulseLocalization.localizedString("provider.summary.separator")
        // Metals present as one asset class across two markets; the preview
        // should name it once.
        var names: [String] = []
        for market in Market.allCases where descriptor.markets.contains(market) {
            let name = market.displayName
            if !names.contains(name) { names.append(name) }
        }
        return names.joined(separator: separator)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.pulseHost) private var host
    @Binding var route: PopoverRoute
    @StateObject private var softwareUpdate = SoftwareUpdateController.shared
    @State private var diagnosticsFeedback: ShareFeedback?

    var body: some View {
        @Bindable var settings = appState.settings

        VStack(spacing: 0) {
            header

            Form {
                Section {
                    Picker(
                        PulseLocalization.localizedString("settings.general.language"),
                        selection: $settings.languagePreference
                    ) {
                        ForEach(PulseLanguagePreference.allCases, id: \.self) { preference in
                            Text(preference.localizedDisplayName).tag(preference)
                        }
                    }
                    Toggle(
                        PulseLocalization.localizedString("settings.general.launchAtLogin"),
                        isOn: $settings.launchAtLogin
                    )
                    settingsDestinationRow(
                        titleKey: "settings.appearance.row",
                        route: .appearanceSettings
                    )
                } header: {
                    Text(PulseLocalization.localizedString("settings.section.general"))
                }

                Section {
                    providerGroupRow(titleKey: "settings.section.providers.accounts", kind: .accounts)
                    providerGroupRow(titleKey: "settings.section.providers.builtin", kind: .builtin)
                } header: {
                    Text(PulseLocalization.localizedString("settings.section.providers"))
                } footer: {
                    if appState.providerDescriptors.allSatisfy({ !appState.isProviderEnabled($0.id) }) {
                        Text(PulseLocalization.localizedString("settings.providers.allDisabled"))
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        route = .mcpSettings
                    } label: {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(PulseLocalization.localizedString(mcpRowStatusKey))
                                    .foregroundStyle(.secondary)
                                settingsChevron
                            }
                        } label: {
                            Text(PulseLocalization.localizedString("settings.mcp.row"))
                        }
                    }
                    .buttonStyle(.pressable)
                } header: {
                    Text(PulseLocalization.localizedString("settings.section.agents"))
                }

                Section {
                    settingsDestinationRow(titleKey: "settings.data.row", route: .dataSettings)
                    Toggle(
                        PulseLocalization.localizedString("settings.general.anonymousAnalytics"),
                        isOn: $settings.shareAnonymousUsageData
                    )
                } header: {
                    Text(PulseLocalization.localizedString("settings.section.data"))
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

                #if DEBUG
                Section {
                    Button(PulseLocalization.localizedString("diagnostics.copy")) {
                        copyDiagnostics()
                    }
                    Button(PulseLocalization.localizedString("onboarding.reset")) {
                        appState.onboarding.reset()
                    }
                }
                #endif
            }
            .formStyle(.grouped)
            .controlSize(.small)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .onAppear { PulseTelemetry.signal(.settingsOpened) }
    }

    private func settingsDestinationRow(titleKey: String, route destination: PopoverRoute) -> some View {
        Button {
            route = destination
        } label: {
            LabeledContent {
                settingsChevron
            } label: {
                Text(PulseLocalization.localizedString(titleKey))
            }
        }
        .buttonStyle(.pressable)
    }

    /// Navigation row into one class of data sources, in the same shape as the
    /// data-and-privacy row below.
    private func providerGroupRow(titleKey: String, kind: ProviderListKind) -> some View {
        Button {
            route = .providerList(kind)
        } label: {
            LabeledContent {
                settingsChevron
            } label: {
                Text(PulseLocalization.localizedString(titleKey))
            }
        }
        .buttonStyle(.pressable)
    }

    private var settingsChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.backHelp")) {
                route = .list
            }
            Text(PulseLocalization.localizedString("settings.title"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, host == .pinnedWindow ? 2 : 8)
        .padding(.bottom, 8)
        .overlay(alignment: .trailing) {
            if let diagnosticsFeedback {
                ShareFeedbackHUD(feedback: diagnosticsFeedback)
                    .padding(.trailing, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                    .allowsHitTesting(false)
            }
        }
    }

    private var mcpRowStatusKey: String {
        switch appState.agentServer?.status {
        case .running:
            "settings.mcp.rowStatus.on"
        case .failed:
            "settings.mcp.rowStatus.attention"
        case .stopped, nil:
            "settings.mcp.rowStatus.off"
        }
    }

    #if DEBUG
    @MainActor
    private func copyDiagnostics() {
        let feedback = ShareFeedback(
            content: .text,
            isSuccess: ReorderDiagnostics.shared.copyLog()
        )
        withAnimation(.snappy(duration: 0.2)) {
            diagnosticsFeedback = feedback
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(feedback.isSuccess ? 1.5 : 3))
            guard diagnosticsFeedback?.id == feedback.id else { return }
            withAnimation(.snappy(duration: 0.2)) {
                diagnosticsFeedback = nil
            }
        }
    }
    #endif
}
