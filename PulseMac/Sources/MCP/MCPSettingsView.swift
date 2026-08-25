import AppKit
import SwiftUI
import PulseCore

/// Settings → Agents → MCP.
///
/// Operate surface: turn the local agent on, expose connection fields, then
/// summarize this MCP server's tools in product language.
struct MCPSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.pulseHost) private var host
    @Binding var route: PopoverRoute

    @State private var tokenRevealed = false
    @State private var confirmingRegenerate = false
    @State private var copyFeedback: ShareFeedback?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                enableCard
                    .padding(.top, 12)

                if !isEnabled {
                    Text(PulseLocalization.localizedString("settings.mcp.intro"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }

                if isEnabled {
                    if case .failed = serverStatus {
                        failureBanner
                    } else {
                        connectionCard
                    }
                }

                toolsCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .animation(.snappy(duration: 0.22), value: isEnabled)
        .animation(.snappy(duration: 0.22), value: statusAnimationToken)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .alert(
            PulseLocalization.localizedString("settings.mcp.regenerateConfirmTitle"),
            isPresented: $confirmingRegenerate
        ) {
            Button(PulseLocalization.localizedString("settings.mcp.regenerate"), role: .destructive) {
                _ = try? appState.agentServer?.rotateToken()
                tokenRevealed = false
            }
            Button(PulseLocalization.localizedString("action.cancel"), role: .cancel) {}
        } message: {
            Text(PulseLocalization.localizedString("settings.mcp.regenerateConfirmMessage"))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.backHelp")) {
                route = .settings
            }
            Text(PulseLocalization.localizedString("settings.mcp.title"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, host == .pinnedWindow ? 2 : 8)
        .padding(.bottom, 8)
        .overlay(alignment: .trailing) {
            if let copyFeedback {
                ShareFeedbackHUD(feedback: copyFeedback)
                    .padding(.trailing, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Enable

    /// Same anatomy as `ProviderEnableCard`: label leading, state + switch trailing.
    private var enableCard: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PulseLocalization.localizedString("settings.mcp.enable"))
                    .font(.system(size: 12, weight: .medium))
                Text(statusCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(
                "",
                isOn: Binding(
                    get: { appState.settings.mcpEnabled },
                    set: { appState.setMCPEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(cardBackground)
    }

    private var failureBanner: some View {
        Text(statusCaption)
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(cardBackground)
    }

    // MARK: - Tools

    /// Product-language summary of this MCP server's tools — not agent marketing copy.
    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PulseLocalization.localizedString("settings.mcp.tools.title"))
                .font(.system(size: 12, weight: .medium))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Self.toolSummaryKeys, id: \.self) { key in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(PulseLocalization.localizedString(key))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(cardBackground)
    }

    private static let toolSummaryKeys = [
        "settings.mcp.tools.read",
        "settings.mcp.tools.watchlist",
        "settings.mcp.tools.trades",
        "settings.mcp.tools.order",
    ]

    // MARK: - Connection fields

    private var connectionCard: some View {
        VStack(spacing: 0) {
            infoRow(
                labelKey: "settings.mcp.type",
                value: PulseLocalization.localizedString("settings.mcp.type.value")
            )

            Divider().padding(.leading, 12)

            fieldRow(
                labelKey: "settings.mcp.endpoint",
                value: endpointText,
                revealed: true
            ) {
                copyValue(appState.agentServer?.endpoint)
            }

            Divider().padding(.leading, 12)

            fieldRow(
                labelKey: "settings.mcp.token",
                value: tokenRevealed ? (token ?? "—") : "••••••••••••",
                revealed: tokenRevealed,
                trailing: {
                    Button {
                        tokenRevealed.toggle()
                    } label: {
                        Image(systemName: tokenRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .help(PulseLocalization.localizedString(
                        tokenRevealed ? "settings.mcp.hideToken" : "settings.mcp.revealToken"
                    ))
                },
                onCopy: { copyValue(token) }
            )

            Divider().padding(.leading, 12)

            Button {
                confirmingRegenerate = true
            } label: {
                Text(PulseLocalization.localizedString("settings.mcp.regenerateToken"))
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
        .background(cardBackground)
    }

    /// Read-only label + value; no copy affordance (protocol name isn't pasted).
    private func infoRow(labelKey: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PulseLocalization.localizedString(labelKey))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func fieldRow<Trailing: View>(
        labelKey: String,
        value: String,
        revealed: Bool,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        onCopy: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PulseLocalization.localizedString(labelKey))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(revealed ? .primary : .secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .help(PulseLocalization.localizedString("settings.mcp.copyField"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.quaternary.opacity(0.35))
    }

    // MARK: - Model

    private var isEnabled: Bool { appState.settings.mcpEnabled }

    private var serverStatus: MCPAgentServer.Status? {
        appState.agentServer?.status
    }

    private var statusAnimationToken: String {
        switch serverStatus {
        case .running(let port): "running.\(port)"
        case .failed(let message): "failed.\(message)"
        case .stopped, nil: "stopped"
        }
    }

    private var statusCaption: String {
        switch serverStatus {
        case .running:
            // Port lives in the endpoint row below — don't repeat it here.
            PulseLocalization.localizedString("settings.mcp.status.running")
        case .failed(let message):
            PulseLocalization.localizedString("settings.mcp.status.failed", message)
        case .stopped, nil:
            PulseLocalization.localizedString("settings.mcp.status.stopped")
        }
    }

    private var endpointText: String {
        appState.agentServer?.endpoint ?? "—"
    }

    private var token: String? {
        try? appState.agentServer?.currentToken()
    }

    private func copyValue(_ value: String?) {
        guard let value else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        let feedback = ShareFeedback(content: .text, isSuccess: true)
        withAnimation(.snappy(duration: 0.2)) {
            copyFeedback = feedback
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard copyFeedback?.id == feedback.id else { return }
            withAnimation(.snappy(duration: 0.2)) {
                copyFeedback = nil
            }
        }
    }
}
