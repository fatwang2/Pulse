import SwiftUI
import PulseCore
import PulseUI

/// Single-trade entry: the side is fixed by the entry point, so the form is
/// just price, quantity, and date, with a live preview of the resulting
/// position. Price and quantity share a compact two-cell row (see
/// `PositionInputCell`); the date rests in the app's own chrome and opens a
/// system calendar only on demand.
struct TradeEntryView: View {
    @Environment(AppState.self) private var appState
    let symbol: SymbolID
    let side: TradeSide
    let returnRoute: PositionReturnRoute
    @Binding var route: PopoverRoute

    @State private var priceText = ""
    @State private var quantityText = ""
    @State private var date = Calendar.current.startOfDay(for: .now)
    @State private var showsCalendar = false
    /// Return can reach `save()` twice in one keypress (field submit + default
    /// action); the first write wins so a trade is never recorded twice.
    @State private var didSave = false

    private var item: WatchItem? { appState.watchlist.item(for: symbol) }
    private var quote: Quote? { appState.market.quote(for: symbol) }
    private var currencyCode: String? { quote?.currencyCode ?? symbol.currencyCode }

    private var sideColor: Color {
        appState.palette.color(isUp: side == .buy)
    }

    private var sideTitle: String {
        PulseLocalization.localizedString(side == .buy ? "trade.buy" : "trade.sell")
    }

    var body: some View {
        VStack(spacing: 0) {
            PositionPageHeader(
                symbol: symbol,
                title: (sideTitle, sideColor),
                onBack: { route = .position(symbol, returnRoute) }
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PositionInputCell(
                        label: PulseLocalization.localizedString("trade.price"),
                        text: $priceText,
                        autofocus: true
                    )
                    PositionInputCell(
                        label: PulseLocalization.localizedString("position.quantity"),
                        text: $quantityText,
                        hint: quantityHint
                    )
                }
                dateRow
                preview
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(PulseLocalization.localizedString("action.cancel")) {
                    route = .position(symbol, returnRoute)
                }
                confirmButton
            }
            .controlSize(.small)
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The whole form is keyboard-first; Return from either field confirms
        // (the button's default action covers Return when no field has focus).
        .onSubmit { save() }
    }

    // MARK: - Form rows

    /// Selling against a long shows what's sellable. Shorts stay unadorned —
    /// negative quantities speak for themselves to anyone shorting.
    private var quantityHint: String? {
        guard side == .sell, let item, item.positionQuantity > 0 else { return nil }
        return PulseLocalization.localizedString(
            "trade.availableToSell",
            PriceFormatter.quantity(item.positionQuantity)
        )
    }

    /// Resting state stays in the app's own chrome: arrows step ±1 day for
    /// the common "today/yesterday" records, and clicking the date opens a
    /// system calendar popover for anything older.
    private var dateRow: some View {
        HStack(spacing: 8) {
            Text(PulseLocalization.localizedString("trade.date"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            IconButton(systemName: "chevron.left", help: "") {
                step(-1)
            }
            Button {
                showsCalendar = true
            } label: {
                Text(dateLabel)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 70)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                CalendarDatePicker(date: $date, maximumDate: .now)
                    .padding(10)
                    .onChange(of: date) { _, _ in
                        showsCalendar = false
                    }
            }
            IconButton(systemName: "chevron.right", help: "") {
                step(1)
            }
            .disabled(isToday)
            .opacity(isToday ? 0.35 : 1)
        }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return PulseLocalization.localizedString("trade.dateToday")
        }
        if calendar.isDateInYesterday(date) {
            return PulseLocalization.localizedString("trade.dateYesterday")
        }
        let formatter = DateFormatter()
        formatter.locale = PulseLocalization.currentLocale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        formatter.dateFormat = sameYear ? "MM-dd" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func step(_ days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        guard next <= Date.now else { return }
        date = next
    }

    // MARK: - Preview (same row styling as the quick-set editor)

    @ViewBuilder
    private var preview: some View {
        let simulated = simulatedOutcome
        let held = item?.positionQuantity ?? 0
        // A trade realizes P&L when it closes against the open side (sell on
        // a long, buy on a short); it moves the average cost when it opens
        // or extends a side. Before input parses, fall back to what the
        // current position implies so rows don't pop in mid-typing.
        let showsRealized = simulated.map { $0.realized != nil }
            ?? (side == .sell ? held > 0 : held < 0)
        let showsAverageCost = simulated.map { $0.quantity != 0 }
            ?? (side == .buy ? held >= 0 : held <= 0)
        VStack(spacing: 6) {
            previewRow(
                PulseLocalization.localizedString("trade.amount"),
                simulated.map { PriceFormatter.money($0.amount, currencyCode: currencyCode) } ?? "—"
            )
            if showsRealized {
                previewRow(
                    PulseLocalization.localizedString("trade.realizedPnL"),
                    simulated?.realized.map { PriceFormatter.signedMoney($0, currencyCode: currencyCode) } ?? "—",
                    color: simulated?.realized
                )
            }
            previewRow(
                PulseLocalization.localizedString("trade.resultingPosition"),
                simulated.map { PriceFormatter.quantity($0.quantity) } ?? "—"
            )
            if showsAverageCost {
                previewRow(
                    PulseLocalization.localizedString("trade.newAverageCost"),
                    simulated.map { newAverageCostText($0) } ?? "—"
                )
            }
        }
        .opacity(simulated == nil ? 0.55 : 1)
    }

    private func previewRow(_ label: String, _ value: String, color: Double? = nil) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(color.map { appState.palette.color(for: $0) } ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .font(.caption)
    }

    private func newAverageCostText(_ outcome: SimulatedOutcome) -> String {
        let new = PriceFormatter.price(outcome.averageCost)
        guard let previous = item?.averageCost else { return new }
        return "\(PriceFormatter.price(previous)) → \(new)"
    }

    // MARK: - Confirm

    /// Solid fill, not glass: the primary action keeps its weight through
    /// color, matching the flat component language of the position pages.
    private var confirmButton: some View {
        Button {
            save()
        } label: {
            Text(PulseLocalization.localizedString(side == .buy ? "trade.confirmBuy" : "trade.confirmSell"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .keyboardShortcut(.defaultAction)
        .help(PulseLocalization.localizedString(
            side == .buy ? "trade.confirmBuyHelp" : "trade.confirmSellHelp"
        ))
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(sideColor.opacity(0.92))
        )
        .disabled(!isValid)
        .opacity(isValid ? 1 : 0.45)
    }

    // MARK: - Parsing & simulation

    private var parsedPrice: Double? {
        parseDecimal(priceText).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private var parsedQuantity: Double? {
        parseDecimal(quantityText).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private var isValid: Bool {
        parsedPrice != nil && parsedQuantity != nil
    }

    private struct SimulatedOutcome {
        var amount: Double
        var realized: Double?
        var quantity: Double
        var averageCost: Double
    }

    /// Replays the would-be ledger (folding legacy lots in, exactly like the
    /// store will on save) so the preview matches the post-save state.
    private var simulatedOutcome: SimulatedOutcome? {
        guard let item, let price = parsedPrice, let quantity = parsedQuantity else { return nil }
        var transactions = item.materializedTransactions()
        transactions.append(PositionTransaction(
            kind: side == .buy ? .buy : .sell,
            price: price,
            quantity: quantity,
            date: date
        ))
        let ledger = PositionLedger(transactions: transactions)
        return SimulatedOutcome(
            amount: price * quantity,
            realized: ledger.entries.last?.realizedPnL,
            quantity: ledger.quantity,
            averageCost: ledger.averageCost
        )
    }

    private func save() {
        guard !didSave, let item, let price = parsedPrice, let quantity = parsedQuantity, isValid else { return }
        didSave = true
        appState.watchlist.addTransaction(item.symbol, PositionTransaction(
            kind: side == .buy ? .buy : .sell,
            price: price,
            quantity: quantity,
            date: date
        ))
        route = .position(symbol, returnRoute)
    }

    private func parseDecimal(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }
}

/// SwiftUI's graphical DatePicker wraps NSDatePicker, whose whole-calendar
/// focus ring can't be disabled from SwiftUI. Wrapping it directly lets us
/// turn the ring off while keeping the system calendar.
private struct CalendarDatePicker: NSViewRepresentable {
    @Binding var date: Date
    var maximumDate: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.datePickerMode = .single
        picker.focusRingType = .none
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.maxDate = maximumDate
        picker.dateValue = date
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.maxDate = maximumDate
        if picker.dateValue != date {
            picker.dateValue = date
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: CalendarDatePicker

        init(_ parent: CalendarDatePicker) {
            self.parent = parent
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            parent.date = sender.dateValue
        }
    }
}
