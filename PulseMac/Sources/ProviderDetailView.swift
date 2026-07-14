import SwiftUI
import PulseCore

/// Enable switch for a data source, presented as a quiet card at the top of its detail page.
struct ProviderEnableCard: View {
    @Environment(AppState.self) private var appState
    let providerID: String

    var body: some View {
        // Full-width card, label leading and switch trailing — the same row anatomy as a
        // grouped-settings toggle, so it aligns with the fact/benefit cards below it.
        HStack {
            Text(PulseLocalization.localizedString("provider.enable"))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Toggle(isOn: Binding(
                get: { appState.isProviderEnabled(providerID) },
                set: { appState.setProvider(providerID, enabled: $0) }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Detail page for data sources without a connection flow (Tencent, Yahoo): the enable
/// switch plus a fact card describing what the source covers.
struct ProviderDetailView: View {
    @Environment(AppState.self) private var appState
    let descriptor: ProviderDescriptor
    @Binding var route: PopoverRoute

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ProviderEnableCard(providerID: descriptor.id)
                    .padding(.top, 12)
                ProviderFactsCard(descriptor: descriptor)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaInset(edge: .top, spacing: 0) { header }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.back")) {
                route = .settings
            }
            Text(descriptor.name)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// Fact card shared by every provider detail page: capabilities, how the app refreshes
/// from this source, then one row per covered market spelling out its exact source
/// freshness — "实时" or the concrete delay in minutes.
struct ProviderFactsCard: View {
    @Environment(AppState.self) private var appState
    let descriptor: ProviderDescriptor

    var body: some View {
        VStack(spacing: 0) {
            factRow(PulseLocalization.localizedString("provider.detail.capabilities")) {
                Text(capabilities)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if descriptor.capabilities.contains(.streaming), appState.longbridgeConfigured {
                Divider().padding(.leading, 12)
                factRow(PulseLocalization.localizedString("provider.refresh.title")) {
                    Text(PulseLocalization.localizedString("provider.refresh.push"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider().padding(.leading, 12)
            // Source latency (the per-market rows below) and poll cadence are different
            // dimensions: a zero-delay source polled every 60s still moves in 60s steps.
            factRow(PulseLocalization.localizedString("provider.refresh.interval")) {
                Picker("", selection: Binding(
                    get: { Int(appState.pollInterval(for: descriptor.id)) },
                    set: { appState.setPollInterval(TimeInterval($0), for: descriptor.id) }
                )) {
                    ForEach([5, 15, 30, 60], id: \.self) { seconds in
                        Text(PulseLocalization.localizedString("duration.seconds", seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            ForEach(coveredMarkets, id: \.self) { market in
                Divider().padding(.leading, 12)
                factRow(market.displayName) {
                    freshnessLabel(for: descriptor.delay[market] ?? 0)
                }
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func factRow(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 12)
            value()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func freshnessLabel(for delay: TimeInterval) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(delay == 0 ? Color.green.opacity(0.8) : .orange)
                .frame(width: 5, height: 5)
            Text(delay == 0
                ? PulseLocalization.localizedString("provider.delay.realtime")
                : PulseLocalization.localizedString("quote.delay.minutes", Int(delay / 60)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var coveredMarkets: [Market] {
        Market.allCases.filter { descriptor.markets.contains($0) }
    }

    private var capabilities: String {
        var parts: [String] = []
        if descriptor.capabilities.contains(.quotes) {
            parts.append(PulseLocalization.localizedString("provider.capability.quotes"))
        }
        if descriptor.capabilities.contains(.candles) {
            parts.append(PulseLocalization.localizedString("provider.capability.candles"))
        }
        if descriptor.capabilities.contains(.search) {
            parts.append(PulseLocalization.localizedString("provider.capability.search"))
        }
        if descriptor.capabilities.contains(.streaming) {
            parts.append(PulseLocalization.localizedString("provider.capability.streaming"))
        }
        return parts.joined(separator: ", ")
    }
}
