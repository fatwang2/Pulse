import AuthenticationServices
import SwiftUI
import PulseCore
import PulseUI

/// App settings: display conventions plus the Longbridge account connection.
/// OAuth runs inside ASWebAuthenticationSession; the callback URL feeds the
/// same authenticator the Mac app uses.
struct SettingsSheet: View {
    @Environment(IOSAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var isAuthorizing = false
    @State private var authorizationFailed = false

    var body: some View {
        NavigationStack {
            Form {
                longbridgeSection
                displaySection
            }
            .navigationTitle(PulseLocalization.localizedString("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label(
                            PulseLocalization.localizedString("action.close"),
                            systemImage: "xmark"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        @Bindable var settings = appState.settings
        return Section(PulseLocalization.localizedString("settings.section.market")) {
            Toggle(
                PulseLocalization.localizedString("settings.market.redUp"),
                isOn: $settings.redUp
            )
            Toggle(
                PulseLocalization.localizedString("settings.market.usExtendedHours"),
                isOn: $settings.showsUSExtendedHours
            )
        }
    }

    // MARK: - Longbridge

    private var longbridgeSection: some View {
        Section {
            if appState.longbridgeConfigured {
                LabeledContent(
                    PulseLocalization.localizedString("longbridge.account"),
                    value: PulseLocalization.localizedString(
                        appState.longbridgeAuthState == .oauth
                            ? "longbridge.status.oauth"
                            : "longbridge.status.apiKey"
                    )
                )
                LabeledContent(
                    PulseLocalization.localizedString("longbridge.connection.title"),
                    value: connectionStatusText
                )
                if case .failed = appState.longbridgeConnectionStatus {
                    Button(PulseLocalization.localizedString("longbridge.connection.retry")) {
                        appState.retryLongbridgeConnection()
                    }
                }
                Button(PulseLocalization.localizedString("longbridge.disconnect"), role: .destructive) {
                    appState.clearLongbridgeCredentials()
                }
            } else {
                Button {
                    startOAuth()
                } label: {
                    if isAuthorizing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(PulseLocalization.localizedString("longbridge.oauth.waiting"))
                        }
                    } else {
                        Text(PulseLocalization.localizedString("longbridge.oauth.connect"))
                    }
                }
                .disabled(isAuthorizing)
                if authorizationFailed {
                    Text(PulseLocalization.localizedString("longbridge.oauth.error"))
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text(PulseLocalization.localizedString("provider.longbridge"))
        } footer: {
            if !appState.longbridgeConfigured {
                Text(PulseLocalization.localizedString("longbridge.setup.intro"))
            }
        }
    }

    private var connectionStatusText: String {
        switch appState.longbridgeConnectionStatus {
        case .disconnected:
            PulseLocalization.localizedString("longbridge.connection.waiting")
        case .connecting:
            PulseLocalization.localizedString("longbridge.connection.connecting")
        case .reconnecting:
            PulseLocalization.localizedString("longbridge.connection.reconnecting")
        case .connected:
            PulseLocalization.localizedString("longbridge.connection.connected")
        case .failed:
            PulseLocalization.localizedString("longbridge.connection.fallback")
        }
    }

    private func startOAuth() {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        authorizationFailed = false
        let scheme = Bundle.main.bundleIdentifier ?? "app.pulse.ios"
        let session = webAuthenticationSession
        let appState = appState
        Task {
            defer { isAuthorizing = false }
            do {
                try await appState.connectLongbridgeOAuth { url in
                    Task { @MainActor in
                        do {
                            let callback = try await session.authenticate(
                                using: url,
                                callbackURLScheme: scheme,
                                preferredBrowserSession: .shared
                            )
                            appState.handleOAuthCallback(callback)
                        } catch {
                            // The user dismissed the sheet: fail the pending flow
                            // now instead of letting it ride the 5-minute timeout.
                            await appState.longbridgeOAuth.cancelAuthorization()
                        }
                    }
                }
            } catch is CancellationError {
                // User-cancelled; no error banner.
            } catch {
                authorizationFailed = true
            }
        }
    }
}
