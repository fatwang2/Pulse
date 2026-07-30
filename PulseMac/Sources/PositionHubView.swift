import SwiftUI
import PulseCore
import PulseUI

/// Position hub: the summary, trade actions, and recent transactions for one
/// holding. Pushed from the detail page (or list); buy/sell/log/quick-set
/// pages push from here and pop back here.
struct PositionHubView: View {
    @Environment(AppState.self) private var appState
    let symbol: SymbolID
    let returnRoute: PositionReturnRoute
    @Binding var route: PopoverRoute

    private var item: WatchItem? { appState.watchlist.item(for: symbol) }
    private var quote: Quote? { appState.market.quote(for: symbol) }
    private var currencyCode: String? { quote?.currencyCode ?? symbol.currencyCode }

    var body: some View {
        VStack(spacing: 0) {
            PositionPageHeader(
                symbol: symbol,
                title: nil,
                onBack: { route = returnRoute.popoverRoute },
                onEdit: { route = .calibrate(symbol, returnRoute) }
            )
            if let item {
                if item.hasPosition {
                    openPositionBody(item)
                } else {
                    emptyBody(item)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Open position

    @ViewBuilder
    private func openPositionBody(_ item: WatchItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let quote, let metrics = PositionMetrics(item: item, quote: quote) {
                HStack(spacing: 8) {
                    pnlCell(PulseLocalization.localizedString("metric.todayPnL"),
                            amount: metrics.todayPnL, percent: metrics.todayReturnPercent)
                    pnlCell(PulseLocalization.localizedString("metric.totalPnL"),
                            amount: metrics.totalPnL, percent: metrics.totalReturnPercent)
                }
                HStack(spacing: 8) {
                    stat(PulseLocalization.localizedString("position.quantity"), PriceFormatter.quantity(metrics.quantity))
                    stat(PulseLocalization.localizedString("position.cost"), PriceFormatter.price(metrics.averageCost))
                    stat(PulseLocalization.localizedString("position.marketValue"), PriceFormatter.money(metrics.marketValue, currencyCode: currencyCode))
                }
                .padding(.top, 10)
            } else {
                Text(PulseLocalization.localizedString("position.waitingQuote"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                stat(
                    PulseLocalization.localizedString("position.realizedPnL"),
                    PriceFormatter.signedMoney(item.realizedPnL, currencyCode: currencyCode),
                    color: item.transactions.isEmpty ? nil : item.realizedPnL
                )
                stat(PulseLocalization.localizedString("position.totalInvested"),
                     PriceFormatter.money(item.costBasis, currencyCode: currencyCode))
                stat("", "")
            }
            .padding(.top, 10)

            separator

            tradeButtons(item, includeSell: true)

            separator

            recentTransactions(item)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func recentTransactions(_ item: WatchItem) -> some View {
        let entries = Array((item.ledger?.entries ?? []).reversed())
        VStack(alignment: .leading, spacing: 0) {
            Text(PulseLocalization.localizedString("position.recentTransactions"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 3)
            ForEach(entries.prefix(3)) { entry in
                TransactionRow(
                    entry: entry,
                    palette: appState.palette,
                    currencyCode: currencyCode
                )
            }
            if entries.isEmpty {
                Text(PulseLocalization.localizedString("position.noTransactions"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            }
            if !entries.isEmpty {
                Button {
                    route = .transactions(symbol, returnRoute)
                } label: {
                    Text(PulseLocalization.localizedString("position.viewAllTransactions", entries.count))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.pressable)
                .padding(.top, 7)
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyBody(_ item: WatchItem) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "briefcase")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 2)
                Text(PulseLocalization.localizedString("position.empty.title"))
                    .font(.system(size: 12, weight: .semibold))
                Text(PulseLocalization.localizedString("position.empty.subtitle"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 14)
            .padding(.bottom, 14)

            tradeButtons(item, includeSell: false)
                .frame(maxWidth: 220)

            Button {
                route = .calibrate(symbol, returnRoute)
            } label: {
                Text(PulseLocalization.localizedString("position.quickSet"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.pressable)
            .padding(.top, 12)

            if !item.transactions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    separator
                    Text(PulseLocalization.localizedString("position.historySection"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                    HStack(spacing: 8) {
                        stat(
                            PulseLocalization.localizedString("position.realizedPnL"),
                            PriceFormatter.signedMoney(item.realizedPnL, currencyCode: currencyCode),
                            color: item.realizedPnL
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PulseLocalization.localizedString("position.historyTrades"))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Button {
                                route = .transactions(symbol, returnRoute)
                            } label: {
                                Text(PulseLocalization.localizedString("position.tradeCount", item.transactions.count))
                                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.pressable)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        stat("", "")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Trade actions

    /// Buy/sell as tinted interactive Liquid Glass buttons; the tint follows
    /// the user's up/down palette so "buy" always reads as the up color.
    private func tradeButtons(_ item: WatchItem, includeSell: Bool) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                tradeButton(
                    includeSell
                        ? PulseLocalization.localizedString("trade.buy")
                        : PulseLocalization.localizedString("trade.recordBuy"),
                    color: appState.palette.color(isUp: true)
                ) {
                    route = .trade(symbol, .buy, returnRoute)
                }
                if includeSell {
                    tradeButton(
                        PulseLocalization.localizedString("trade.sell"),
                        color: appState.palette.color(isUp: false)
                    ) {
                        route = .trade(symbol, .sell, returnRoute)
                    }
                }
            }
        }
    }

    private func tradeButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .glassEffect(
            .regular.tint(color.opacity(0.22)).interactive(),
            in: .rect(cornerRadius: 8, style: .continuous)
        )
    }

    // MARK: - Cells (mirrors the detail page's stat styling)

    private var separator: some View {
        Rectangle()
            .fill(.separator.opacity(0.55))
            .frame(height: 0.5)
            .padding(.vertical, 12)
    }

    private func pnlCell(_ label: String, amount: Double, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(PriceFormatter.signedMoney(amount, currencyCode: currencyCode))
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                Text(PriceFormatter.percent(percent))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .opacity(0.9)
            }
            .foregroundStyle(appState.palette.color(for: amount))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String, color: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 10.5, weight: color == nil ? .medium : .semibold).monospacedDigit())
                .foregroundStyle(color.map { appState.palette.color(for: $0) } ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared position-page chrome

/// Back chevron + instrument identity, matching the detail page's header row.
struct PositionPageHeader: View {
    @Environment(AppState.self) private var appState
    let symbol: SymbolID
    /// Optional leading emphasis ("买入"/"卖出"), tinted by the caller.
    var title: (text: String, color: Color)?
    let onBack: () -> Void
    /// Optional trailing edit affordance (the hub's quick-set entry).
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.back")) {
                onBack()
            }
            HStack(spacing: 6) {
                if let title {
                    Text(title.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(title.color)
                        .fixedSize()
                }
                Text(appState.displayName(for: symbol))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                MarketBadge(market: symbol.market)
                    .fixedSize()
                Text(symbol.displayCode)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onEdit {
                ClusterIcon(
                    systemName: "square.and.pencil",
                    help: PulseLocalization.localizedString("position.quickEditTitle")
                ) {
                    onEdit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// One transaction line: date, kind badge, quantity @ price (sells append
/// their realized P&L), and the trade amount.
struct TransactionRow: View {
    let entry: PositionLedger.Entry
    let palette: ChangePalette
    let currencyCode: String?
    /// Hover-revealed delete affordance (full log page only).
    var onDelete: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(PositionDateFormat.monthDay(entry.transaction.date))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .leading)
            TradeKindBadge(kind: entry.transaction.kind, palette: palette)
            (Text("\(PriceFormatter.quantity(entry.transaction.quantity)) @ \(PriceFormatter.price(entry.transaction.price))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.primary)
             + realizedSuffix)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var realizedSuffix: Text {
        guard let realized = entry.realizedPnL else { return Text("") }
        return Text("  \(PriceFormatter.signedMoney(realized, currencyCode: currencyCode))")
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(palette.color(for: realized))
    }

    @ViewBuilder
    private var trailing: some View {
        if let onDelete, hovering {
            IconButton(systemName: "xmark", help: PulseLocalization.localizedString("action.delete")) {
                onDelete()
            }
        } else if entry.transaction.kind == .adjustment {
            Text(PulseLocalization.localizedString("transaction.overwrite"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        } else {
            Text(PriceFormatter.money(
                entry.transaction.price * entry.transaction.quantity,
                currencyCode: currencyCode
            ))
            .font(.system(size: 10.5).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

struct TradeKindBadge: View {
    let kind: PositionTransaction.Kind
    let palette: ChangePalette

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(kind == .adjustment ? 0.12 : 0.15))
            )
    }

    private var label: String {
        switch kind {
        case .buy: PulseLocalization.localizedString("transaction.kind.buy")
        case .sell: PulseLocalization.localizedString("transaction.kind.sell")
        case .adjustment: PulseLocalization.localizedString("transaction.kind.adjustment")
        }
    }

    private var color: Color {
        switch kind {
        case .buy: palette.color(isUp: true)
        case .sell: palette.color(isUp: false)
        case .adjustment: .secondary
        }
    }
}

/// Compact numeric input cell shared by the trade form and quick-set editor:
/// label above, monospaced input below — same DNA as the hub's stat cells,
/// sized for a short number rather than a full-width system form row.
struct PositionInputCell: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    @Binding var text: String
    /// Small trailing note beside the label (e.g. "可卖 200").
    var hint: String?
    var hintIsWarning = false
    var autofocus = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                if let hint {
                    Text(hint)
                        .font(.system(size: 9))
                        .foregroundStyle(hintIsWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                        .lineLimit(1)
                }
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                .focused($isFocused)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isFocused
                        ? AnyShapeStyle(Color.accentColor.opacity(0.6))
                        : AnyShapeStyle(.separator.opacity(0.5)),
                    lineWidth: isFocused ? 1 : 0.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .task {
            // Grabbing focus mid-push fails while the panel is still
            // animating; land it just after the 0.28s route transition.
            guard autofocus else { return }
            try? await Task.sleep(for: .milliseconds(360))
            isFocused = true
        }
    }
}

enum PositionDateFormat {
    /// "07-28" — fixed numeric layout matching the app's monospaced columns.
    static func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = PulseLocalization.currentLocale
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    /// Localized month group header, e.g. "2026年7月" / "July 2026".
    static func monthGroup(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = PulseLocalization.currentLocale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: date)
    }
}
