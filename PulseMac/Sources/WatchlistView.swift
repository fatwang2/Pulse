import OSLog
import SwiftUI
import PulseCore
import PulseUI

private let watchlistReorderLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.pulse.mac",
    category: "WatchlistReorder"
)

/// Search UI state shared between the list page and the popover root: the root
/// keeps it alive across detail pushes and uses it to size the search panel.
struct SearchSession {
    var text = ""
    var isActive = false
    var cache: [String: [SymbolInfo]] = [:]
}

private enum PulseExternalLinks {
    static let website = URL(string: "https://www.pulseticker.app/?utm_source=pulse_macos&utm_medium=app&utm_campaign=menu_links&utm_content=official_website")!
    static let github = URL(string: "https://github.com/fatwang2/Pulse?utm_source=pulse_macos&utm_medium=app&utm_campaign=menu_links&utm_content=github_repository")!
}

struct WatchlistView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulseHost) private var host
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Binding var route: PopoverRoute

    @Binding var searchSession: SearchSession
    @FocusState private var searchFieldFocused: Bool
    @State private var searchResults: [SymbolInfo] = []
    @State private var completedSearchQuery: String?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var refreshHovering = false
    @State private var isReordering = false
    @State private var shareFeedback: ShareFeedback?
    @State private var hostWindow: NSWindow?
    @AppStorage("pulse.watchlist.orderMode.v1") private var listOrderMode = WatchlistOrderMode.manual.rawValue
    @AppStorage("pulse.watchlist.sortOption.v1") private var listSortOption = WatchlistSortOption.changePercent.rawValue

    private enum SearchTerminalState: Equatable {
        case none
        case failure(String)
        case noResults
    }

    var body: some View {
        VStack(spacing: 0) {
            // Keep the chrome in the layout so the first rows never render behind
            // the brand, actions, or group tabs. A safe-area inset still lets List
            // content underlap its inset on macOS, which makes the chrome unreadable.
            chrome

            ZStack {
                baseContent
                    .opacity(searchSession.isActive ? 0 : 1)
                    .allowsHitTesting(!searchSession.isActive)
                // Focusing the field is entering search: an empty query shows recent
                // queries (or a hint) and typing swaps them for live results.
                searchEmptyPanel
                    .opacity(searchSession.isActive && searchSession.text.isEmpty ? 1 : 0)
                    .allowsHitTesting(searchSession.isActive && searchSession.text.isEmpty)
                searchList
                    .opacity(searchSession.isActive && !searchSession.text.isEmpty ? 1 : 0)
                    .allowsHitTesting(searchSession.isActive && !searchSession.text.isEmpty)
            }
            // Crossfade the watchlist ↔ search swap; within search it only fires at the
            // empty ↔ non-empty boundary, so typing stays instant after the first character.
            .animation(.easeOut(duration: 0.15), value: searchSession.isActive)
            .animation(.easeOut(duration: 0.15), value: searchSession.text.isEmpty)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollEdgeEffectStyle(.soft, for: .all)

            bottomBar
                .frame(height: 30)
                .opacity(searchSession.isActive ? 0 : 1)
                .allowsHitTesting(!searchSession.isActive)
        }
        // Every enter/exit path (adjust action, Done, sort menu, group switch) funnels
        // through this one state, so the quote-write hold can't leak in either direction.
        .onChange(of: isReordering) { _, active in
            appState.setUserReordering(active)
            if active {
                watchlistReorderLogger.info(
                    "Reorder mode entered; itemCount=\(appState.watchlist.items.count, privacy: .public)"
                )
                #if DEBUG
                ReorderDiagnostics.shared.reorderModeEntered(
                    itemCount: appState.watchlist.items.count,
                    orderMode: listOrderMode,
                    sortOption: listSortOption,
                    prioritizesOpenMarkets: appState.settings.prioritizeOpenMarkets,
                    reduceMotion: reduceMotion
                )
                #endif
            } else {
                watchlistReorderLogger.info("Reorder mode exited")
                #if DEBUG
                ReorderDiagnostics.shared.reorderModeExited()
                #endif
            }
        }
        .onAppear { maybeStartTour() }
        // Only the host currently carrying the tour may pause it: the panel
        // closing must not interrupt a bubble shown in the pinned window.
        .onDisappear {
            if isTourHost { appState.onboarding.pauseTour() }
        }
        .onChange(of: appState.watchlist.allItems.isEmpty) { _, isEmpty in
            // A first symbol from any path retires the search step.
            if !isEmpty { appState.onboarding.completeStep(.search) }
            maybeStartTour()
        }
        .onChange(of: searchSession.isActive) { _, active in
            if active {
                // Opening search is the search step performed; later steps pause.
                appState.onboarding.completeStep(.search)
                if isTourHost { appState.onboarding.pauseTour() }
            } else {
                maybeStartTour()
            }
        }
        .onChange(of: route) { _, newRoute in
            if newRoute == .list {
                maybeStartTour()
            } else {
                // Opening any detail page is the detail step performed. The share
                // stop belongs to that page and must survive this transition.
                if case .detail = newRoute { appState.onboarding.completeStep(.detail) }
                if isTourHost, let step = appState.onboarding.activeTourStep, step != .kline {
                    appState.onboarding.pauseTour()
                }
            }
        }
        // The detail page moves the resume position on its way out (share seen,
        // pin next); by then the route is already back on the list, so that
        // route change alone would have checked too early.
        .onChange(of: appState.onboarding.tourResumeStep) { _, _ in maybeStartTour() }
    }

    @ViewBuilder
    private var baseContent: some View {
        if appState.watchlist.items.isEmpty {
            emptyState
        } else {
            TimelineView(.periodic(from: .now, by: 3600)) { context in
                watchList(at: context.date)
            }
        }
    }

    // MARK: - Floating chrome (header + search field)

    // MARK: Actions

    /// The share and more menus' contents, shared by both renderings of the action
    /// cluster below so the menus themselves are defined once.
    @ViewBuilder private var shareMenuContent: some View {
        Button {
            copyShareImage()
        } label: {
            Label(
                PulseLocalization.localizedString("action.copyAsImage"),
                systemImage: "photo"
            )
        }
        Button {
            copyShareText()
        } label: {
            Label(
                PulseLocalization.localizedString("action.copyAsText"),
                systemImage: "doc.text"
            )
        }
    }

    @ViewBuilder private var moreMenuContent: some View {
        Menu {
            ForEach(WatchRowMetricMode.allCases, id: \.self) { mode in
                Toggle(mode.displayName, isOn: metricModeBinding(mode))
            }
        } label: {
            Text(PulseLocalization.localizedString("watchlist.menu.display"))
        }
        Divider()
        Menu {
            // State group: where the current order comes from (checkmark semantics).
            Toggle(
                PulseLocalization.localizedString("watchlist.sort.manual"),
                isOn: orderModeBinding(.manual)
            )

            Divider()

            ForEach(WatchlistSortOption.allCases) { option in
                Toggle(option.title, isOn: sortOptionBinding(option))
            }

            Divider()

            // Action: enter the drag-to-reorder state for the arrangement on screen.
            Button {
                beginAdjustingOrder()
            } label: {
                Text(PulseLocalization.localizedString(
                    isReordering ? "watchlist.sort.adjustActive" : "watchlist.sort.adjust"
                ))
            }
            .disabled(isReordering)
        } label: {
            Text(PulseLocalization.localizedString("watchlist.menu.sort"))
        }
        Divider()
        Button {
            NSWorkspace.shared.open(PulseExternalLinks.website)
        } label: {
            Text(PulseLocalization.localizedString("action.openWebsite"))
        }
        Button {
            NSWorkspace.shared.open(PulseExternalLinks.github)
        } label: {
            Text(PulseLocalization.localizedString("action.openGitHub"))
        }
        Divider()
        Button {
            route = .settings
        } label: {
            Text(PulseLocalization.localizedString("settings.title"))
        }
        Divider()
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Text(PulseLocalization.localizedString("action.quitPulse"))
        }
    }

    private var pinHelp: String {
        PulseLocalization.localizedString(isPinned ? "action.unpinWindow" : "action.pinWindow")
    }

    /// The panel's action cluster: `ClusterIcon` draws its own compact chip, including
    /// the tinted background that marks an active toggle.
    @ViewBuilder private var actionButtons: some View {
        // The glyph names what the control governs; whether it is lit says if the window
        // is up. A `pin.slash` for the on-state would read as "off" — a slash means muted
        // or disabled everywhere else — and would clash with the search toggle beside it,
        // which already states its state rather than its action.
        ClusterIcon(
            systemName: "pin",
            help: pinHelp,
            isActive: isPinned
        ) {
            togglePinnedWindow()
        }
        .popover(isPresented: tourBinding(.pin), arrowEdge: .bottom) {
            tourBubble(.pin)
        }
        ClusterIcon(
            systemName: "magnifyingglass",
            help: PulseLocalization.localizedString("action.search"),
            isActive: searchSession.isActive
        ) {
            toggleSearch()
        }
        .disabled(isReordering)
        .opacity(isReordering ? 0.45 : 1)
        // The tour teaches the magnifier, not the empty state's one-time button:
        // this is where search still lives after the first symbol.
        .popover(isPresented: tourBinding(.search), arrowEdge: .bottom) {
            tourBubble(.search)
        }
        ClusterMenu(
            systemName: "square.and.arrow.up",
            help: PulseLocalization.localizedString("action.share")
        ) {
            shareMenuContent
        }
        .disabled(appState.watchlist.items.isEmpty)
        .opacity(appState.watchlist.items.isEmpty ? 0.45 : 1)
        ClusterMenu(systemName: "ellipsis.circle", help: PulseLocalization.localizedString("action.more")) {
            moreMenuContent
        }
        .frame(height: 26)
    }

    /// The same actions for the pinned window's title bar, as plain toolbar controls.
    ///
    /// A toolbar already owns this treatment: it draws the container and the selected
    /// state for its items. Reusing `ClusterIcon` here nested its own tinted chip inside
    /// the system's, leaving two chips with mismatched corners.
    ///
    /// The pin is a plain button, not a lit toggle. While this window is up the pin is
    /// always "on", so any selected chrome — accent, primary, or secondary gray — would
    /// sit permanently in the title-bar corner and outweigh quieter neighbors. The
    /// window's existence is the on-state; the control only needs to offer unpin.
    /// Search stays a toggle: its accent chrome is brief.
    @ViewBuilder private var toolbarActions: some View {
        Button {
            togglePinnedWindow()
        } label: {
            Label(pinHelp, systemImage: "pin")
        }
        .help(pinHelp)
        .popover(isPresented: tourBinding(.pin), arrowEdge: .bottom) {
            tourBubble(.pin)
        }

        Toggle(isOn: Binding(get: { searchSession.isActive }, set: { _ in toggleSearch() })) {
            Label(PulseLocalization.localizedString("action.search"), systemImage: "magnifyingglass")
        }
        .toggleStyle(.button)
        .help(PulseLocalization.localizedString("action.search"))
        .disabled(isReordering)
        .popover(isPresented: tourBinding(.search), arrowEdge: .bottom) {
            tourBubble(.search)
        }

        Menu {
            shareMenuContent
        } label: {
            Label(
                PulseLocalization.localizedString("action.share"),
                systemImage: "square.and.arrow.up"
            )
        }
        .menuIndicator(.hidden)
        .help(PulseLocalization.localizedString("action.share"))
        .disabled(appState.watchlist.items.isEmpty)

        Menu {
            moreMenuContent
        } label: {
            Label(
                PulseLocalization.localizedString("action.more"),
                systemImage: "ellipsis.circle"
            )
        }
        .menuIndicator(.hidden)
        .help(PulseLocalization.localizedString("action.more"))
    }

    @ViewBuilder private var shareFeedbackOverlay: some View {
        if let shareFeedback {
            ShareFeedbackHUD(feedback: shareFeedback)
                .padding(.trailing, host == .pinnedWindow ? 0 : 62)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                .allowsHitTesting(false)
        }
    }

    private var chrome: some View {
        VStack(spacing: 7) {
            // The pinned window has a title bar of its own; its actions move up into it
            // rather than repeating a brand row underneath.
            if host == .menuBar {
                HStack(spacing: 8) {
                    PulseWaveformMark(primaryColor: .accentColor)
                        .frame(width: 15, height: 11.5)
                        .frame(width: 17, height: 13, alignment: .trailing)
                        .accessibilityHidden(true)
                    // Bundle display name: "Pulse Dev" in Debug builds, "Pulse" in Release
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Pulse")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    actionButtons
                }
                .overlay(alignment: .trailing) {
                    shareFeedbackOverlay
                }
            }
            WatchlistGroupBar(isDisabled: isReordering, onSelect: selectGroup)
            if searchSession.isActive {
                searchField
            }
        }
        .overlay(alignment: .topTrailing) {
            // The panel hangs this off its header row. With the pinned window's actions
            // up in the title bar, the copy confirmation lands just under them instead.
            if host == .pinnedWindow {
                shareFeedbackOverlay
            }
        }
        .padding(.horizontal, 12)
        // The system title bar already supplies separation below its controls.
        // Keep the pinned surface compact instead of stacking the panel's full
        // top inset on top of that built-in spacing.
        .padding(.top, host == .pinnedWindow ? 5 : 10)
        .padding(.bottom, 7)
        .animation(.snappy(duration: 0.18), value: searchSession.isActive)
        .background {
            // Standard find shortcut; keeps working while the button itself is hidden chrome.
            Button("", action: activateSearch)
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .background {
            HostWindowReader { hostWindow = $0 }
        }
        // Keep the list's toolbar skeleton mounted while a child page covers it.
        // The list itself stays mounted to preserve scroll position; removing its
        // toolbar at route change would also remove 20pt of safe area and make the
        // outgoing list jump upward before its horizontal exit begins.
        .toolbar {
            if host == .pinnedWindow {
                ToolbarSpacer(.flexible)
                if route == .list {
                    ToolbarItemGroup(placement: .primaryAction) {
                        toolbarActions
                    }
                }
            }
        }
    }

    /// Pinned state is a property of the app, not of the surface reading it: the panel
    /// opened while the window is already up shows the same "unpin" affordance rather
    /// than a pin that would do nothing.
    private var isPinned: Bool { appState.settings.pinnedWindowVisible }

    /// Pinning hands the watchlist over to the floating window: park it where the panel
    /// stands so it reads as detaching in place, open it, bring the app forward (an
    /// accessory app is not frontmost, so the window would otherwise surface behind
    /// whatever the user was in), then close the panel, which does not dismiss itself
    /// for a click inside its own bounds. Unpinning closes the window from either
    /// surface; the menu bar icon always brings the watchlist back.
    private func togglePinnedWindow() {
        // Clicking the pin while its tip points at it is the tip followed:
        // retire it instead of re-offering on the next visit.
        if appState.onboarding.activeTourStep == .pin {
            appState.onboarding.endTour()
        }
        guard !isPinned else {
            dismissWindow(id: PinnedWindow.id)
            return
        }
        if let panel = hostWindow {
            PinnedWindow.pendingTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        }
        openWindow(id: PinnedWindow.id)
        PinnedWindow.activate()
        hostWindow?.close()
    }

    // MARK: - Onboarding tour

    /// Both hosts render the same shared tour, but only one carries it at a
    /// time: the pinned window when it is up, else the menu bar panel.
    private var isTourHost: Bool {
        host == .pinnedWindow || !appState.settings.pinnedWindowVisible
    }

    private func tourBinding(_ step: OnboardingState.TourStep) -> Binding<Bool> {
        Binding(
            // Gated on the list route: while a child page covers this view its
            // anchors are off screen, and the pin stop set up from the detail
            // page must wait for the trip back.
            get: { isTourHost && route == .list && appState.onboarding.activeTourStep == step },
            set: { presented in
                // Interactive dismissal is disabled; this fires for lifecycle
                // teardown (host closing under an open bubble). Pause, not skip.
                if !presented, appState.onboarding.activeTourStep == step {
                    appState.onboarding.pauseTour()
                }
            }
        )
    }

    private func tourBubble(_ step: OnboardingState.TourStep) -> OnboardingTourBubble {
        let key = switch step {
        case .search:
            "onboarding.tour.search"
        case .detail:
            "onboarding.tour.detail"
        case .kline:
            // Anchored in DetailView; listed here only for exhaustiveness.
            "onboarding.tour.kline"
        case .pin:
            // The same control, opposite meanings: the window's pin tucks Pulse
            // away, the panel's pin breaks it out.
            host == .pinnedWindow ? "onboarding.tour.pin.window" : "onboarding.tour.pin.panel"
        }
        return OnboardingTourBubble(
            step: step,
            text: PulseLocalization.localizedString(key),
            onAdvance: tourAdvanceAction(step)
        )
    }

    /// Next on an action step performs the taught action itself; the step then
    /// completes through the same observers as a manual click. The bubble is
    /// retired first and the action follows a beat later: overlapping the
    /// popover's dismissal with a page transition reads as two unrelated
    /// animations fighting, where the ordinary navigation has only one.
    private func tourAdvanceAction(_ step: OnboardingState.TourStep) -> (() -> Void)? {
        switch step {
        case .search:
            {
                appState.onboarding.completeStep(.search)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    activateSearch()
                }
            }
        case .detail:
            {
                appState.onboarding.completeStep(.detail)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    if let first = appState.watchlist.items.first {
                        route = .detail(first.symbol)
                    }
                }
            }
        case .kline, .pin:
            nil
        }
    }

    /// The pending stop's anchor must be on this page: the search step lives on
    /// the empty state, detail and pin on a populated list, and share not here
    /// at all — the detail page offers that one itself.
    private var tourAnchorAvailable: Bool {
        switch appState.onboarding.tourResumeStep {
        case .search:
            appState.watchlist.items.isEmpty
        case .detail, .pin:
            !appState.watchlist.items.isEmpty
        case .kline:
            false
        }
    }

    /// Starts (or resumes) the tour while the list is the quiet foreground:
    /// no search, no reorder, no pushed page, and the next stop's anchor visible.
    private func maybeStartTour() {
        guard isTourHost,
              appState.onboarding.tourAvailable,
              appState.onboarding.activeTourStep == nil,
              tourAnchorAvailable,
              !searchSession.isActive,
              !isReordering,
              route == .list else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard isTourHost,
                  appState.onboarding.tourAvailable,
                  appState.onboarding.activeTourStep == nil,
                  tourAnchorAvailable,
                  !searchSession.isActive,
                  !isReordering,
                  route == .list else { return }
            appState.onboarding.beginTourIfNeeded()
        }
    }

    private func activateSearch() {
        guard !isReordering else { return }
        searchSession.isActive = true
        focusSearchField()
    }

    private func focusSearchField() {
        Task { @MainActor in
            // The field is inserted conditionally. Let SwiftUI finish that update
            // before asking it to become the first responder.
            await Task.yield()
            guard searchSession.isActive else { return }
            searchFieldFocused = true
        }
    }

    private func toggleSearch() {
        if searchSession.isActive {
            exitSearch()
        } else {
            activateSearch()
        }
    }

    private func exitSearch() {
        searchSession.text = ""
        searchSession.isActive = false
        searchFieldFocused = false
    }

    private func selectGroup(_ id: UUID) {
        guard appState.watchlist.selectedGroupID != id else { return }
        exitSearch()
        isReordering = false

        // Switching tags is a high-frequency navigation action. Apply the final
        // list state in one non-animated transaction so rows do not look as if
        // they were individually inserted, removed, and sorted.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            appState.watchlist.selectGroup(id)
            if listOrderMode == WatchlistOrderMode.manual.rawValue {
                _ = appState.watchlist.restoreManualOrder()
                enforcePinnedOrder()
            } else if let option = WatchlistSortOption(rawValue: listSortOption) {
                applySort(option, animated: false)
            }
        }
    }

    private var watchRowMetricColumnWidth: CGFloat {
        let mode = appState.settings.watchRowMetricMode
        let widths = displayedItems().map { item -> CGFloat in
            let quote = appState.market.quote(for: item.symbol)
            let metrics = quote.flatMap { PositionMetrics(item: item, quote: $0) }
            let display = WatchRow.rowMetricDisplay(
                quote: quote,
                metrics: metrics,
                mode: mode,
                item: item,
                palette: appState.palette
            )
            let priceText = quote.map { PriceFormatter.price($0.price, market: item.symbol.market) } ?? "—"
            let sessionLabel = appState.isIndex(item.symbol)
                ? nil
                : quote?.marketState?.extendedSessionLabel
            return WatchRowColumnLayout.metricWidth(
                priceText: priceText,
                metricText: display.text,
                sessionLabel: sessionLabel,
                presentation: .popover
            )
        }
        return widths.max() ?? 52
    }

    private var watchRowTitleColumnWidth: CGFloat {
        let widths = displayedItems().map { item in
            WatchRowColumnLayout.titleWidth(
                name: item.resolvedDisplayName,
                symbolCode: item.symbol.displayCode,
                marketName: item.symbol.market.displayName,
                presentation: .popover,
                trailingAccessoryWidth: appState.watchlist.isPinned(item.symbol) ? 11 : 0
            )
        }
        return widths.max() ?? 48
    }

    private func displayedItems(at date: Date = .now) -> [WatchItem] {
        WatchlistDisplayOrder.items(
            from: appState.watchlist,
            prioritizeOpenMarkets: appState.settings.prioritizeOpenMarkets,
            at: date,
            bypass: isReordering
        )
    }

    /// Health line with the manual-refresh button beside it. With per-provider cadences and
    /// push updates there is no single "refreshed at" moment anymore, so the line carries
    /// health only: a status dot, plus the fallback notice when a source is failing.
    private var footer: some View {
        HStack(spacing: 5) {
            if isReordering {
                Text(PulseLocalization.localizedString("status.reorderHint"))
            } else {
                Circle()
                    .fill(footerShowsFallback ? .orange : Color.green.opacity(0.8))
                    .frame(width: 6, height: 6)
                if footerShowsFallback {
                    Text(PulseLocalization.localizedString("status.providerFallback"))
                } else if appState.liveStreaming {
                    Text(PulseLocalization.localizedString("status.streaming"))
                } else {
                    Text(PulseLocalization.localizedString("status.healthy"))
                }
                Button {
                    PulseTelemetry.signal(.manualRefreshRequested)
                    appState.engine.poke()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(refreshHovering ? .primary : .secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(refreshHovering ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.pressable)
                .onHover { refreshHovering = $0 }
                .help(PulseLocalization.localizedString("action.refreshNow"))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(height: 22)
        .padding(.leading, 12)
        .padding(.bottom, 4)
    }

    private var bottomBar: some View {
        HStack {
            footer
            Spacer()
            if isReordering {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { isReordering = false }
                } label: {
                    Label(PulseLocalization.localizedString("action.done"), systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .padding(.trailing, 12)
                .padding(.bottom, 4)
            }
        }
    }

    private var footerShowsFallback: Bool {
        if appState.market.lastError != nil { return true }
        guard appState.longbridgeConfigured,
              appState.isProviderEnabled(LongbridgeProvider.providerID) else { return false }
        if case .failed = appState.longbridgeConnectionStatus { return true }
        return false
    }

    @MainActor
    private func copyShareImage() {
        do {
            let snapshot = WatchlistShareSnapshot(appState: appState)
            let palette = ChangePalette(redUp: snapshot.redUp)
            let card = PulseShareCard(
                ambientColor: snapshot.ambientChange.map(palette.color(for:))
            ) {
                WatchlistShareContent(snapshot: snapshot)
            }
            let artifact = try ShareImageRenderer.render(
                card,
                configuration: .watchlistSquare(
                    height: snapshot.preferredImageHeight,
                    colorScheme: colorScheme,
                    locale: appState.settings.locale
                )
            )
            try ClipboardImageExporter.write(artifact)
            showShareFeedback(content: .image, isSuccess: true)
        } catch {
            showShareFeedback(content: .image, isSuccess: false)
        }
    }

    @MainActor
    private func copyShareText() {
        do {
            let snapshot = WatchlistTextSnapshot(appState: appState)
            try ClipboardTextExporter.write(snapshot.renderedText())
            showShareFeedback(content: .text, isSuccess: true)
        } catch {
            showShareFeedback(content: .text, isSuccess: false)
        }
    }

    @MainActor
    private func showShareFeedback(content: ShareFeedback.Content, isSuccess: Bool) {
        let feedback = ShareFeedback(content: content, isSuccess: isSuccess)
        withAnimation(.snappy(duration: 0.2)) {
            shareFeedback = feedback
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(isSuccess ? 1.5 : 3))
            guard shareFeedback?.id == feedback.id else { return }
            withAnimation(.snappy(duration: 0.2)) {
                shareFeedback = nil
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(PulseLocalization.localizedString("search.placeholder"), text: $searchSession.text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFieldFocused)
                // Two-stage escape, matching NSSearchField: clear the query first,
                // then collapse back to the list (a further Esc closes the popover).
                .onExitCommand {
                    if searchSession.text.isEmpty {
                        exitSearch()
                    } else {
                        searchSession.text = ""
                    }
                }
                .onAppear { focusSearchField() }
            if isSearching {
                ProgressView().controlSize(.mini)
            } else if !searchSession.text.isEmpty {
                Button {
                    searchSession.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 0.5)
        }
        .disabled(isReordering)
        .opacity(isReordering ? 0.45 : 1)
        .task(id: searchSession.text) {
            let query = normalizedSearchQuery(searchSession.text)
            guard shouldRunSearch(for: query) else {
                isSearching = false
                searchResults = []
                searchError = nil
                completedSearchQuery = nil
                return
            }
            let cacheKey = normalizedSearchCacheKey(query)
            if let cached = searchSession.cache[cacheKey] {
                isSearching = false
                searchResults = cached
                searchError = nil
                completedSearchQuery = query
                return
            }
            isSearching = true
            searchResults = []
            searchError = nil
            completedSearchQuery = nil
            defer {
                if query == normalizedSearchQuery(searchSession.text) {
                    isSearching = false
                }
            }
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                let results = try await appState.search(query)
                try Task.checkCancellation()
                guard query == normalizedSearchQuery(searchSession.text) else { return }
                // Never make a transient all-source failure sticky for the lifetime
                // of the popover. Successful results remain instant on repeat search.
                if !results.isEmpty {
                    searchSession.cache[cacheKey] = results
                }
                searchResults = results
                searchError = nil
                completedSearchQuery = query
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, query == normalizedSearchQuery(searchSession.text) else { return }
                searchResults = []
                searchError = shortErrorText(error)
                completedSearchQuery = query
            }
        }
    }

    private var searchList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(searchResults) { info in
                    SearchResultRow(
                        info: info,
                        onOpen: { openSearchResult(info) },
                        onAdd: { addSearchResult(info) },
                        onRemove: { removeSearchResult(info) }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never, axes: .vertical)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .overlay {
            switch searchTerminalState {
            case .failure(let searchError):
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    Text(PulseLocalization.localizedString("search.failed")).font(.callout)
                    Text(searchError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .transition(.opacity)
            case .noResults:
                Text(PulseLocalization.localizedString("search.noResults"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            case .none:
                EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.15), value: searchTerminalState)
    }

    /// Search is active but nothing is typed yet: recent queries first (when any),
    /// then curated popular symbols as one-click starting points.
    private var searchEmptyPanel: some View {
        let queries = appState.settings.recentSearchQueries
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !queries.isEmpty {
                    HStack {
                        Text(PulseLocalization.localizedString("search.recent.title"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(PulseLocalization.localizedString("search.recent.clear")) {
                            appState.settings.clearRecentSearches()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                    ChipFlowLayout(spacing: 6) {
                        ForEach(queries, id: \.self) { query in
                            SearchChip(label: query) {
                                // Re-recording moves the query back to the front of the list
                                appState.settings.recordRecentSearch(query)
                                searchSession.text = query
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }

                Text(PulseLocalization.localizedString("search.hot.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, queries.isEmpty ? 10 : 16)
                    .padding(.bottom, 8)

                ChipFlowLayout(spacing: 6) {
                    ForEach(hotSymbols) { hot in
                        SearchChip(label: hot.localizedName(isChinese: usesChineseNames)) {
                            // Tapping a suggestion is itself a deliberate search
                            let query = hot.query(isChinese: usesChineseNames)
                            appState.settings.recordRecentSearch(query)
                            searchSession.text = query
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never, axes: .vertical)
    }

    private var usesChineseNames: Bool {
        appState.settings.locale.language.languageCode?.identifier == "zh"
    }

    /// Curated starting points, not live rankings: familiar names across the
    /// markets Pulse covers, so an empty panel is never a dead end.
    private var hotSymbols: [HotSymbol] {
        [
            HotSymbol(code: "AAPL", zhName: "苹果", enName: "Apple", zhQuery: "AAPL"),
            HotSymbol(code: "NVDA", zhName: "英伟达", enName: "NVIDIA", zhQuery: "NVDA"),
            HotSymbol(code: "TSLA", zhName: "特斯拉", enName: "Tesla", zhQuery: "TSLA"),
            HotSymbol(code: "SPY", zhName: "标普500 ETF", enName: "S&P 500 ETF", zhQuery: "SPY"),
            HotSymbol(code: "00700", zhName: "腾讯控股", enName: "Tencent", zhQuery: "腾讯", enQuery: "Tencent"),
            HotSymbol(code: "09988", zhName: "阿里巴巴", enName: "Alibaba", zhQuery: "阿里巴巴", enQuery: "Alibaba"),
            HotSymbol(code: "600519", zhName: "贵州茅台", enName: "Kweichow Moutai", enQuery: "600519"),
            HotSymbol(code: "BTC", zhName: "比特币", enName: "Bitcoin", zhQuery: "BTC"),
        ]
    }

    private var searchTerminalState: SearchTerminalState {
        let query = normalizedSearchQuery(searchSession.text)
        guard completedSearchQuery == query, shouldRunSearch(for: query) else {
            return .none
        }
        if let searchError { return .failure(searchError) }
        if searchResults.isEmpty { return .noResults }
        return .none
    }

    private func normalizedSearchQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedSearchCacheKey(_ query: String) -> String {
        query.lowercased()
    }

    private func shouldRunSearch(for query: String) -> Bool {
        !query.isEmpty
    }

    /// Opens the quote page without adding; the search session survives at the
    /// popover root, so backing out lands on the same results.
    private func openSearchResult(_ info: SymbolInfo) {
        appState.settings.recordRecentSearch(normalizedSearchQuery(searchSession.text))
        route = .detail(info.symbol)
    }

    private func addSearchResult(_ info: SymbolInfo) {
        let queryAtAddition = normalizedSearchQuery(searchSession.text)
        appState.settings.recordRecentSearch(queryAtAddition)
        appState.watchlist.add(info)
        appState.engine.poke()

        // Keep the result visible just long enough for its plus icon to become a
        // checkmark, then return to the selected list.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard normalizedSearchQuery(searchSession.text) == queryAtAddition else { return }
            exitSearch()
        }
    }

    /// Unlike adding, removal stays on the results so the user can keep curating.
    private func removeSearchResult(_ info: SymbolInfo) {
        appState.watchlist.remove(info.symbol)
    }

    private func shortErrorText(_ error: any Error) -> String {
        if let providerError = error as? ProviderError {
            return switch providerError {
            case .network(let detail): PulseLocalization.localizedString("error.network", detail)
            case .rateLimited: PulseLocalization.localizedString("error.rateLimited")
            case .clientError(_, let detail): PulseLocalization.localizedString("error.client", detail)
            case .badResponse(let detail): detail
            case .unsupported: PulseLocalization.localizedString("error.unsupported")
            case .symbolNotFound: PulseLocalization.localizedString("error.symbolNotFound")
            }
        }
        return error.localizedDescription
    }

    // MARK: - Watchlist

    @State private var emptyStateShown = false

    /// First-run is the one rare moment that earns an entrance: icon and text
    /// fade up with a short stagger. Reduced motion drops the offset, keeps the fade.
    private var emptyState: some View {
        let shouldAnimateEntrance = appState.watchlist.isEmpty
        return VStack(spacing: 10) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34))
                .foregroundStyle(.quaternary)
                .opacity(shouldAnimateEntrance ? (emptyStateShown ? 1 : 0) : 1)
                .offset(y: shouldAnimateEntrance && !emptyStateShown && !reduceMotion ? 6 : 0)
                .animation(
                    shouldAnimateEntrance ? .snappy(duration: 0.35) : nil,
                    value: emptyStateShown
                )
            Text(PulseLocalization.localizedString("empty.watchlist"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(shouldAnimateEntrance ? (emptyStateShown ? 1 : 0) : 1)
                .offset(y: shouldAnimateEntrance && !emptyStateShown && !reduceMotion ? 6 : 0)
                .animation(
                    shouldAnimateEntrance ? .snappy(duration: 0.35).delay(0.06) : nil,
                    value: emptyStateShown
                )
            // The hint made clickable: same action as the magnifying glass above, so
            // the first add teaches where search lives without leaving this screen.
            Button {
                activateSearch()
            } label: {
                Label(
                    PulseLocalization.localizedString("empty.searchButton"),
                    systemImage: "magnifyingglass"
                )
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glassProminent)
            .padding(.top, 6)
            .opacity(shouldAnimateEntrance ? (emptyStateShown ? 1 : 0) : 1)
            .offset(y: shouldAnimateEntrance && !emptyStateShown && !reduceMotion ? 6 : 0)
            .animation(
                shouldAnimateEntrance ? .snappy(duration: 0.35).delay(0.12) : nil,
                value: emptyStateShown
            )
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { emptyStateShown = true }
        .onDisappear { emptyStateShown = false }
    }

    private func watchList(at date: Date) -> some View {
        let items = displayedItems(at: date)
        let titleColumnWidth = watchRowTitleColumnWidth
        let metricColumnWidth = watchRowMetricColumnWidth
        return List {
            ForEach(items) { item in
                WatchRow(
                    item: item,
                    titleColumnWidth: titleColumnWidth,
                    metricColumnWidth: metricColumnWidth,
                    isPinned: appState.watchlist.isPinned(item.symbol),
                    isReordering: isReordering
                ) {
                    route = .detail(item.symbol)
                }
                // The detail stop anchors on the first row: one bubble, not one per row.
                .popover(
                    isPresented: item.symbol == items.first?.symbol
                        ? tourBinding(.detail)
                        : .constant(false),
                    arrowEdge: .bottom
                ) {
                    tourBubble(.detail)
                }
                // Inset 4 + the row's internal 8pt padding puts row content on the same 12pt grid as the chrome
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                .listRowSeparator(.hidden)
                .moveDisabled(!isReordering)
                .contextMenu {
                    if !isReordering {
                        Toggle(
                            PulseLocalization.localizedString("watchlist.sort.pinToTop"),
                            isOn: pinnedBinding(item.symbol)
                        )
                        Divider()
                        Button(PulseLocalization.localizedString("action.pinToMenuBar")) {
                            appState.settings.primarySymbol = item.symbol
                            appState.settings.menuBarMode = .single
                            appState.settings.showPriceInMenuBar = true
                        }
                        if item.supportsPosition {
                            Button(PulseLocalization.localizedString("action.editPosition")) {
                                route = .position(item.symbol, .list)
                            }
                        }
                        Menu(PulseLocalization.localizedString("watchlist.group.membership")) {
                            ForEach(appState.watchlist.groups) { group in
                                // Toggle renders as a native checkmark menu
                                // item; a Label's icon does not survive menu
                                // rendering on macOS.
                                Toggle(group.name, isOn: membershipBinding(item.symbol, group.id))
                            }
                        }
                        Divider()
                        Button(PulseLocalization.localizedString("watchlist.sort.adjust")) {
                            beginAdjustingOrder()
                        }
                        if let currentGroup = appState.watchlist.selectedGroup {
                            Divider()
                            Button(
                                PulseLocalization.localizedString(
                                    "watchlist.group.removeCurrent",
                                    currentGroup.name
                                ),
                                role: .destructive
                            ) {
                                withAnimation(.snappy(duration: 0.22)) {
                                    appState.watchlist.setMembership(
                                        item.symbol,
                                        in: currentGroup.id,
                                        included: false
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .onMove { source, destination in
                watchlistReorderLogger.info(
                    "List onMove received; sourceCount=\(source.count, privacy: .public) destination=\(destination, privacy: .public)"
                )
                // Reorder always edits the persisted baseline. Session grouping is
                // bypassed while `isReordering` so indices match `group.symbols`.
                let currentSymbols = appState.watchlist.items.map(\.symbol)
                let movingSymbols = source
                    .filter { currentSymbols.indices.contains($0) }
                    .sorted()
                    .map { currentSymbols[$0] }
                var orderedSymbols = currentSymbols
                orderedSymbols.move(fromOffsets: source, toOffset: destination)
                let committed = appState.watchlist.commitManualMove(
                    orderedSymbols: orderedSymbols,
                    movingSymbols: movingSymbols
                )
                watchlistReorderLogger.info(
                    "List move commit completed; success=\(committed, privacy: .public)"
                )
                #if DEBUG
                ReorderDiagnostics.shared.moveReceived(
                    sourceCount: source.count,
                    destination: destination,
                    itemCount: currentSymbols.count,
                    committed: committed
                )
                #endif
                if committed {
                    listOrderMode = WatchlistOrderMode.manual.rawValue
                }
            }
        }
        .listStyle(.plain)
        // macOS List keeps a host-level horizontal margin even after row insets
        // are customized. Remove it so the row surface shares the chrome/footer
        // 12pt rail; WatchRow's own 8pt padding still protects its text and prices.
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background {
            #if DEBUG
            ReorderPointerMonitor(enabled: isReordering)
            #else
            EmptyView()
            #endif
        }
        // A persistent AppKit scroller becomes a heavy dark rail in this compact
        // glass popover. The system soft edge effect communicates overflow while
        // keeping scrolling, keyboard navigation, and List reordering unchanged.
        .scrollIndicators(.never, axes: .vertical)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .animation(.snappy(duration: 0.16), value: items.map(\.symbol))
    }

    /// Membership as a menu Toggle binding: unchecking the current group slides
    /// the row out of this list; unchecking the last group removes the symbol
    /// from the watchlist entirely.
    private func membershipBinding(_ symbol: SymbolID, _ groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { appState.watchlist.contains(symbol, in: groupID) },
            set: { included in
                withAnimation(.snappy(duration: 0.22)) {
                    appState.watchlist.setMembership(symbol, in: groupID, included: included)
                }
            }
        )
    }

    private func pinnedBinding(_ symbol: SymbolID) -> Binding<Bool> {
        Binding(
            get: { appState.watchlist.isPinned(symbol) },
            set: { pinned in
                let usesAutomaticSort = listOrderMode == WatchlistOrderMode.automatic.rawValue
                if !usesAutomaticSort {
                    // Capture the unpinned baseline before the pin membership changes.
                    appState.watchlist.rememberManualOrder()
                }
                guard appState.watchlist.setPinned(symbol, pinned: pinned) else { return }
                withAnimation(.snappy(duration: 0.16)) {
                    if usesAutomaticSort,
                       let option = WatchlistSortOption(rawValue: listSortOption) {
                        applySort(option)
                    } else {
                        _ = appState.watchlist.restoreManualOrder()
                        enforcePinnedOrder()
                    }
                }
            }
        )
    }

    /// State switch: bring back the remembered custom order. Does not enter the reorder UI.
    private func selectCustomOrder() {
        searchSession.text = ""
        withAnimation(.snappy(duration: 0.16)) {
            _ = appState.watchlist.restoreManualOrder()
            enforcePinnedOrder()
        }
        listOrderMode = WatchlistOrderMode.manual.rawValue
    }

    /// Custom order remains stable within the pinned and unpinned sections.
    /// Dragging across their boundary cannot leave a pinned row below a regular row.
    private func enforcePinnedOrder() {
        appState.watchlist.reorder(
            WatchlistSortResolver.pinnedFirstSymbols(
                items: appState.watchlist.items,
                pinnedSymbols: appState.watchlist.selectedGroup?.pinnedSymbols ?? []
            )
        )
    }

    /// Action: start adjusting the arrangement currently on screen. Order mode and the remembered
    /// custom order stay untouched until the first actual drag (onMove commits both), so exiting
    /// without dragging changes nothing.
    private func beginAdjustingOrder() {
        searchSession.text = ""
        withAnimation(.snappy(duration: 0.25)) { isReordering = true }
    }

    private func applySort(_ option: WatchlistSortOption, animated: Bool = true) {
        if listOrderMode == WatchlistOrderMode.manual.rawValue {
            appState.watchlist.rememberManualOrder()
        }

        let sortedSymbols = WatchlistSortResolver.sortedSymbols(
            items: appState.watchlist.items,
            pinnedSymbols: appState.watchlist.selectedGroup?.pinnedSymbols ?? []
        ) { item in
            sortValue(for: item, option: option)
        }

        searchSession.text = ""
        isReordering = false
        listOrderMode = WatchlistOrderMode.automatic.rawValue
        listSortOption = option.rawValue
        if animated {
            withAnimation(.snappy(duration: 0.16)) {
                appState.watchlist.reorder(sortedSymbols)
            }
        } else {
            appState.watchlist.reorder(sortedSymbols)
        }
    }

    private func metricModeBinding(_ mode: WatchRowMetricMode) -> Binding<Bool> {
        Binding(
            get: { appState.settings.watchRowMetricMode == mode },
            set: { isSelected in
                guard isSelected else { return }
                appState.settings.watchRowMetricMode = mode
            }
        )
    }

    private func orderModeBinding(_ mode: WatchlistOrderMode) -> Binding<Bool> {
        Binding(
            get: { listOrderMode == mode.rawValue },
            // Menu radio semantics: selecting an item always fires, even when already checked
            // (a checked Toggle sends `false` on click). Restoring is idempotent, so this is safe.
            set: { _ in
                switch mode {
                case .manual:
                    selectCustomOrder()
                case .automatic:
                    break
                }
            }
        )
    }

    private func sortOptionBinding(_ option: WatchlistSortOption) -> Binding<Bool> {
        Binding(
            get: {
                listOrderMode == WatchlistOrderMode.automatic.rawValue
                    && listSortOption == option.rawValue
            },
            set: { isSelected in
                guard isSelected else { return }
                applySort(option)
            }
        )
    }

    private func sortValue(for item: WatchItem, option: WatchlistSortOption) -> Double? {
        guard let quote = appState.market.quote(for: item.symbol) else { return nil }
        let metrics = PositionMetrics(item: item, quote: quote)
        switch option {
        case .changePercent:
            return quote.changePercent
        case .todayPnL:
            return metrics?.todayPnL
        case .totalPnL:
            return metrics?.totalPnL
        case .marketValue:
            return metrics?.marketValue
        }
    }
}

// MARK: - Components

enum WatchlistSortResolver {
    static func pinnedFirstSymbols(
        items: [WatchItem],
        pinnedSymbols: [SymbolID]
    ) -> [SymbolID] {
        let itemsBySymbol = Dictionary(uniqueKeysWithValues: items.map { ($0.symbol, $0) })
        let pinned = Set(pinnedSymbols)
        return pinnedSymbols.filter { itemsBySymbol[$0] != nil }
            + items.filter { !pinned.contains($0.symbol) }.map(\.symbol)
    }

    static func sortedSymbols(
        items: [WatchItem],
        pinnedSymbols: [SymbolID],
        value: (WatchItem) -> Double?
    ) -> [SymbolID] {
        let pinned = Set(pinnedSymbols)
        return items.enumerated().sorted { lhs, rhs in
            let leftIsPinned = pinned.contains(lhs.element.symbol)
            let rightIsPinned = pinned.contains(rhs.element.symbol)
            if leftIsPinned != rightIsPinned { return leftIsPinned }

            let left = value(lhs.element)
            let right = value(rhs.element)
            switch (left, right) {
            case let (left?, right?):
                if left == right { return lhs.offset < rhs.offset }
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map { $0.element.symbol }
    }
}

private enum WatchlistOrderMode: String {
    case manual
    case automatic
}

private enum WatchlistSortOption: String, CaseIterable, Identifiable {
    case changePercent
    case todayPnL
    case totalPnL
    case marketValue

    var id: Self { self }

    var title: String {
        switch self {
        case .changePercent: PulseLocalization.localizedString("sort.changePercent")
        case .todayPnL: PulseLocalization.localizedString("sort.todayPnL")
        case .totalPnL: PulseLocalization.localizedString("sort.totalPnL")
        case .marketValue: PulseLocalization.localizedString("sort.marketValue")
        }
    }
}

/// Compact icon button for popover chrome.
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Menu variant of `ClusterIcon`: same compact chrome look, but opens a menu instead of firing an action.
struct ClusterMenu<Content: View>: View {
    let systemName: String
    let help: String
    @ViewBuilder let content: Content
    @State private var hovering = false

    init(systemName: String, help: String, @ViewBuilder content: () -> Content) {
        self.systemName = systemName
        self.help = help
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Small icon button for dense menu-bar popover chrome.
struct ClusterIcon: View {
    let systemName: String
    let help: String
    var isActive: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : (hovering ? .primary : .secondary))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.12)
                              : (hovering ? Color.primary.opacity(0.08) : .clear))
                )
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct HotSymbol: Identifiable {
    let code: String
    let zhName: String
    let enName: String
    var zhQuery: String?
    var enQuery: String?

    var id: String { code }

    func localizedName(isChinese: Bool) -> String {
        isChinese ? zhName : enName
    }

    /// The query that most reliably surfaces this instrument through the search
    /// providers; defaults to the localized name for CN/HK names, the code otherwise.
    func query(isChinese: Bool) -> String {
        if isChinese { return zhQuery ?? zhName }
        return enQuery ?? code
    }
}

/// Leading-aligned wrap layout for natural-width chips: each chip hugs its label,
/// rows fill left-to-right, and the ragged right edge keeps a scannable left rail.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One chip style for every search shortcut; the section headers carry the semantics.
struct SearchChip: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
            // A hierarchical fill stays visible over the popover's vibrancy material;
            // hover jumps a full step so the affordance is unmistakable.
            .background(.quaternary.opacity(hovering ? 1 : 0.45), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct SearchResultRow: View {
    @Environment(AppState.self) private var appState
    let info: SymbolInfo
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        let isIncluded = appState.watchlist.contains(info.symbol)
        let selectedGroupName = appState.watchlist.selectedGroup?.name ?? ""
        let addLabel = PulseLocalization.localizedString("search.addToGroup", selectedGroupName)
        let removeLabel = PulseLocalization.localizedString(
            "watchlist.group.removeCurrent",
            selectedGroupName
        )

        // The row navigates to the quote page; the trailing accessory toggles
        // membership in the selected group — checkmark is a click-to-remove.
        Button(action: onOpen) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.resolvedDisplayName)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        MarketBadge(market: info.symbol.market)
                        Text(info.symbol.displayCode)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(.secondary)
                        if let typeLabel {
                            Text(typeLabel)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                if isIncluded {
                    Button(action: onRemove) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .help(removeLabel)
                    .accessibilityLabel(removeLabel)
                } else {
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.tint)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .help(addLabel)
                    .accessibilityLabel(addLabel)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(hovering ? Color.primary.opacity(0.05) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PulseLocalization.localizedString("search.viewDetail", info.resolvedDisplayName))
        .onHover { hovering = $0 }
    }

    private var typeLabel: String? {
        switch info.type {
        // The market badge already names these; a second tag would repeat it.
        case .equity, .crypto, .commodity:
            nil
        case .etf:
            "ETF"
        case .index:
            PulseLocalization.localizedString("assetType.index")
        case .fund:
            PulseLocalization.localizedString("assetType.fund")
        case .other:
            nil
        }
    }
}

struct WatchRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: WatchItem
    let titleColumnWidth: CGFloat
    let metricColumnWidth: CGFloat
    var isPinned: Bool = false
    var isReordering: Bool = false
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        let quote = appState.market.quote(for: item.symbol)
        let change = quote?.change ?? 0
        let color = appState.palette.color(for: change)
        let metrics = quote.flatMap { PositionMetrics(item: item, quote: $0) }
        let metricMode = appState.settings.watchRowMetricMode
        let metricDisplay = Self.rowMetricDisplay(
            quote: quote,
            metrics: metrics,
            mode: metricMode,
            item: item,
            palette: appState.palette
        )
        let priceText = quote.map { PriceFormatter.price($0.price, market: item.symbol.market) } ?? "—"
        // Indices don't trade pre/post; their quote is just the last regular
        // print, so a session label would mislabel it.
        let sessionLabel = appState.isIndex(item.symbol)
            ? nil
            : quote?.marketState?.extendedSessionLabel

        // In manual sort mode, row tap gestures are fully detached so List's reorder drag can own mousedown.
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                // The list's widest required title establishes one shared column; the aligned remainder goes to every sparkline.
                VStack(alignment: .leading, spacing: 2.5) {
                    titleLabel
                    HStack(spacing: 4) {
                        MarketBadge(market: item.symbol.market)
                        Text(item.symbol.displayCode)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: titleColumnWidth, alignment: .leading)

                // The list sparkline always frames the regular session: at row
                // size the pre/post wings read as noise. The detail chart is
                // where the extended-hours setting applies.
                IntradaySparklineView(
                    candles: appState.market.sparklines[item.symbol] ?? [],
                    previousClose: quote?.previousClose,
                    market: item.symbol.market,
                    tint: color,
                    includesExtendedHours: false
                )
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
            }
            .contentShape(Rectangle())
            .gesture(TapGesture().onEnded { onOpen() }, isEnabled: !isReordering)

            VStack(alignment: .trailing, spacing: 2.5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let sessionLabel {
                        Text(sessionLabel)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Text(priceText)
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)
                        // numericText(value:) rolls digits up on an uptick and down on a downtick;
                        // the scoped .animation supplies the transaction that quote refreshes lack.
                        // Animate the same magnitude the string prints so a third decimal the
                        // market allows stays in sync with the transition.
                        .contentTransition(
                            reduceMotion
                                ? .opacity
                                : .numericText(value: PriceFormatter.animatablePrice(
                                    quote?.price ?? 0,
                                    market: item.symbol.market
                                ))
                        )
                        .animation(.snappy(duration: 0.25), value: priceText)
                }
                rowMetricView(display: metricDisplay)
            }
            .frame(width: metricColumnWidth, alignment: .trailing)
            .layoutPriority(2)
            .contentShape(Rectangle())
            // Fast path for switching the metric column (THS-style): tap the numbers to cycle.
            // The open-detail tap is scoped to the name/sparkline group, so the two never double-fire.
            .gesture(TapGesture().onEnded {
                appState.settings.watchRowMetricMode = appState.settings.watchRowMetricMode.next
            }, isEnabled: !isReordering)
            .help(PulseLocalization.localizedString("watchRow.metricHelp"))

            if isReordering {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .help(PulseLocalization.localizedString("watchRow.dragHelp"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hovering || isReordering ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        // AppKit owns the drag session once List starts moving a row. Updating local
        // hover state while the pointer crosses rows rebuilds their hosting views and
        // can invalidate the native drop indicator on macOS 26.
        .onHover { isHovering in
            guard !isReordering else { return }
            hovering = isHovering
        }
        .onChange(of: isReordering) { _, active in
            if active { hovering = false }
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        HStack(spacing: 3) {
            let label = Text(item.resolvedDisplayName)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            if WatchRowColumnLayout.nameIsTruncated(
                item.resolvedDisplayName,
                availableWidth: titleColumnWidth - (isPinned ? 11 : 0),
                presentation: .popover
            ) {
                label.help(item.resolvedDisplayName)
            } else {
                label
            }

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .help(PulseLocalization.localizedString("watchlist.sort.pinned"))
                    .accessibilityLabel(PulseLocalization.localizedString("watchlist.sort.pinned"))
            }
        }
    }

    @ViewBuilder
    private func rowMetricView(quote: Quote?, metrics: PositionMetrics?, mode: WatchRowMetricMode) -> some View {
        let display = Self.rowMetricDisplay(
            quote: quote,
            metrics: metrics,
            mode: mode,
            item: item,
            palette: appState.palette
        )
        rowMetricView(display: display)
    }

    @ViewBuilder
    private func rowMetricView(display: (text: String, color: Color)) -> some View {
        Text(display.text)
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(display.color)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .allowsTightening(true)
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(.snappy(duration: 0.25), value: display.text)
    }

    static func rowMetricDisplay(
        quote: Quote?,
        metrics: PositionMetrics?,
        mode: WatchRowMetricMode,
        item: WatchItem,
        palette: ChangePalette
    ) -> (text: String, color: Color) {
        let display = WatchRowMetricDisplay.resolve(
            quote: quote,
            metrics: metrics,
            mode: mode,
            item: item
        )
        return (
            display.text,
            display.colorValue.map(palette.color(for:)) ?? .secondary
        )
    }

}
