import SwiftUI
import PulseCore
import PulseUI

/// Full transaction log, newest first and grouped by month. V1 deliberately
/// supports delete-only (no per-entry editing): a mistaken entry is deleted
/// and re-recorded, which keeps replay semantics unambiguous.
struct TransactionListView: View {
    @Environment(AppState.self) private var appState
    let symbol: SymbolID
    let returnRoute: PositionReturnRoute
    @Binding var route: PopoverRoute

    @State private var pendingDeletion: PositionLedger.Entry?

    private var item: WatchItem? { appState.watchlist.item(for: symbol) }
    private var quote: Quote? { appState.market.quote(for: symbol) }
    private var currencyCode: String? { quote?.currencyCode ?? symbol.currencyCode }

    private var entries: [PositionLedger.Entry] {
        Array((item?.ledger?.entries ?? []).reversed())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(monthGroups, id: \.title) { group in
                        Text(group.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        ForEach(group.entries) { entry in
                            TransactionRow(
                                entry: entry,
                                palette: appState.palette,
                                currencyCode: currencyCode,
                                onDelete: { pendingDeletion = entry }
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: entries.isEmpty) { _, isEmpty in
            // Deleting the last entry leaves nothing to show here.
            if isEmpty { route = .position(symbol, returnRoute) }
        }
        .alert(
            PulseLocalization.localizedString("transaction.deleteConfirmTitle"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { entry in
            Button(PulseLocalization.localizedString("action.delete"), role: .destructive) {
                appState.watchlist.deleteTransaction(symbol, id: entry.transaction.id)
                pendingDeletion = nil
            }
            Button(PulseLocalization.localizedString("action.cancel"), role: .cancel) {
                pendingDeletion = nil
            }
        } message: { entry in
            Text(deletionSummary(entry))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.back")) {
                route = .position(symbol, returnRoute)
            }
            HStack(spacing: 6) {
                Text(PulseLocalization.localizedString("transaction.logTitle"))
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize()
                Text("\(symbol.displayCode) · \(PulseLocalization.localizedString("position.tradeCount", entries.count))")
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private struct MonthGroup {
        var title: String
        var entries: [PositionLedger.Entry]
    }

    /// Entries are already newest-first; walking them in order keeps months
    /// sorted without a second pass.
    private var monthGroups: [MonthGroup] {
        var groups: [MonthGroup] = []
        for entry in entries {
            let title = PositionDateFormat.monthGroup(entry.transaction.date)
            if groups.last?.title == title {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append(MonthGroup(title: title, entries: [entry]))
            }
        }
        return groups
    }

    private func deletionSummary(_ entry: PositionLedger.Entry) -> String {
        let kind = switch entry.transaction.kind {
        case .buy: PulseLocalization.localizedString("transaction.kind.buy")
        case .sell: PulseLocalization.localizedString("transaction.kind.sell")
        case .adjustment: PulseLocalization.localizedString("transaction.kind.adjustment")
        }
        return PulseLocalization.localizedString(
            "transaction.deleteConfirmMessage",
            PositionDateFormat.monthDay(entry.transaction.date),
            kind,
            PriceFormatter.quantity(entry.transaction.quantity),
            PriceFormatter.price(entry.transaction.price)
        )
    }
}
