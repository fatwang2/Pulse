import SwiftUI
import PulseCore

/// Second-level settings page listing one class of data sources. Account sources
/// are things to connect; built-ins are toggles that just work — each class gets
/// its own page so the settings root stays short as sources accumulate.
struct ProviderListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.pulseHost) private var host
    let kind: ProviderListKind
    @Binding var route: PopoverRoute

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                Section {
                    ForEach(descriptors, id: \.id) { descriptor in
                        ProviderRow(descriptor: descriptor) {
                            route = .providerDetail(descriptor.id)
                        }
                    }
                } footer: {
                    Text(PulseLocalization.localizedString(
                        kind == .accounts ? "settings.providers.accounts.help" : "settings.providers.help"
                    ))
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    private var descriptors: [ProviderDescriptor] {
        appState.providerDescriptors.filter {
            kind == .accounts ? !$0.credentials.isEmpty : $0.credentials.isEmpty
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.backHelp")) {
                route = .settings
            }
            Text(PulseLocalization.localizedString(
                kind == .accounts ? "settings.section.providers.accounts" : "settings.section.providers.builtin"
            ))
            .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, host == .pinnedWindow ? 2 : 8)
        .padding(.bottom, 8)
    }
}
