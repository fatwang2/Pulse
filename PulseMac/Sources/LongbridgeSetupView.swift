import SwiftUI
import PulseCore

/// Longbridge detail page, in the same card language as every other provider page:
/// enable switch → shared fact card → an account card that carries the connection flow
/// (browser OAuth as the primary action, manual API-key entry one level deeper).
/// Secrets go to the Keychain only after a live validation round-trip; stored values are
/// never displayed back, only overwritten.
struct LongbridgeSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var route: PopoverRoute

    @State private var showManualFields = false
    @State private var appKey = ""
    @State private var appSecret = ""
    @State private var accessToken = ""
    @State private var isConnecting = false
    @State private var connectionError: String?
    @FocusState private var focusedField: CredentialField?

    private enum CredentialField {
        case appKey, appSecret, accessToken
    }

    private var configured: Bool { appState.longbridgeConfigured }
    private var enabled: Bool { appState.isProviderEnabled(LongbridgeProvider.providerID) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    // The switch is locked until an account is connected; connecting
                    // flips it on automatically, disconnecting locks it off again.
                    ProviderEnableCard(providerID: LongbridgeProvider.providerID, locked: !configured)
                        .padding(.top, 12)
                    // Behavior facts only apply to a source that is actually running.
                    if configured && enabled {
                        ProviderFactsCard(descriptor: appState.longbridge.descriptor)
                    }
                    // The account card always stays: it is the way in (connect) and
                    // the way out (disconnect).
                    accountCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: showManualFields) { _, shown in
                guard shown else { return }
                focusedField = .appKey
                // Let the expansion lay out first, then bring the fields into view.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    withAnimation(.snappy(duration: 0.25)) {
                        proxy.scrollTo("manualFields", anchor: .bottom)
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: showManualFields)
        .animation(.snappy(duration: 0.25), value: configured)
        .animation(.snappy(duration: 0.25), value: enabled)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaInset(edge: .top, spacing: 0) { header }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.back")) {
                route = .settings
            }
            Text(PulseLocalization.localizedString("provider.longbridge"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Account card

    private var accountCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(PulseLocalization.localizedString("longbridge.account"))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Circle()
                    .fill(configured ? Color.green.opacity(0.85) : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(PulseLocalization.localizedString(statusKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider().padding(.leading, 12)

            VStack(spacing: 10) {
                if configured {
                    actionButton(titleKey: "longbridge.disconnect", tint: .red) {
                        appState.clearLongbridgeCredentials()
                        setConnectionError(nil)
                        showManualFields = false
                    }
                    .disabled(isConnecting)
                } else {
                    Text(PulseLocalization.localizedString("longbridge.setup.intro"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    actionButton(
                        titleKey: isConnecting ? "longbridge.oauth.waiting" : "longbridge.oauth.connect",
                        tint: .accentColor,
                        showsSpinner: isConnecting
                    ) {
                        connectOAuth()
                    }
                    .disabled(isConnecting)

                    Button {
                        showManualFields.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(PulseLocalization.localizedString("longbridge.setup.manualToggle"))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .rotationEffect(.degrees(showManualFields ? 180 : 0))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)

                    if showManualFields {
                        manualFields
                            .id("manualFields")
                    }
                }

                if let connectionError {
                    Text(connectionError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .transition(connectionErrorTransition)
                }
            }
            .padding(12)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var statusKey: String {
        switch appState.longbridgeAuthState {
        case .oauth: "longbridge.status.oauth"
        case .apiKey: "longbridge.status.apiKey"
        case .none: "provider.status.notConnected"
        }
    }

    /// Full-width action in the app's quiet-surface idiom: tint lives in the text, feedback
    /// lands on mouse-down via `.pressable` — no filled color slabs.
    private func actionButton(titleKey: String, tint: Color, showsSpinner: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsSpinner {
                    ProgressView().controlSize(.mini)
                }
                Text(PulseLocalization.localizedString(titleKey))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Manual credentials (fallback)

    private var manualFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            credentialField("App Key", text: $appKey, field: .appKey, secure: false)
            credentialField("App Secret", text: $appSecret, field: .appSecret)
            credentialField("Access Token", text: $accessToken, field: .accessToken)
            HStack(alignment: .top) {
                Text(PulseLocalization.localizedString("longbridge.credentials.help"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(PulseLocalization.localizedString("longbridge.credentials.save")) {
                    saveManualCredentials()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!fieldsComplete || isConnecting)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Text field in the app's own input idiom (the search field): plain field on a quiet
    /// surface with a hairline separator stroke; the stroke picks up the accent on focus.
    private func credentialField(_ placeholder: String, text: Binding<String>,
                                 field: CredentialField, secure: Bool = true) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12))
        .focused($focusedField, equals: field)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    focusedField == field
                        ? AnyShapeStyle(Color.accentColor.opacity(0.6))
                        : AnyShapeStyle(.separator.opacity(0.35)),
                    lineWidth: focusedField == field ? 1 : 0.5
                )
        }
        .animation(.easeOut(duration: 0.15), value: focusedField == field)
    }

    private var fieldsComplete: Bool {
        [appKey, appSecret, accessToken].allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var connectionErrorTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
    }

    private var connectionErrorAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.15 : 0.18)
    }

    @MainActor
    private func setConnectionError(_ message: String?) {
        withAnimation(connectionErrorAnimation) {
            connectionError = message
        }
    }

    // MARK: - Actions

    private func connectOAuth() {
        isConnecting = true
        setConnectionError(nil)
        Task {
            do {
                try await appState.connectLongbridgeOAuth()
                showManualFields = false
            } catch {
                setConnectionError(PulseLocalization.localizedString("longbridge.oauth.error"))
            }
            isConnecting = false
        }
    }

    private func saveManualCredentials() {
        let credentials = LongbridgeCredentials(
            appKey: appKey.trimmingCharacters(in: .whitespaces),
            appSecret: appSecret.trimmingCharacters(in: .whitespaces),
            accessToken: accessToken.trimmingCharacters(in: .whitespaces)
        )
        isConnecting = true
        setConnectionError(nil)
        Task {
            do {
                try await appState.saveLongbridgeCredentials(credentials)
                appKey = ""
                appSecret = ""
                accessToken = ""
                showManualFields = false
            } catch {
                setConnectionError(PulseLocalization.localizedString("longbridge.credentials.error"))
            }
            isConnecting = false
        }
    }
}
