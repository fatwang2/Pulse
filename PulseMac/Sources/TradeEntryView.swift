import SwiftUI
import PulseCore
import PulseUI

/// Single-trade entry: the side is fixed by the entry point, so the form is
/// just price, quantity, and date, with a live preview of the resulting
/// position. Price and quantity share a compact two-cell row (see
/// `PositionInputCell`); the date rests in the app's own chrome and opens a
/// system calendar only on demand.
///
/// With `editing` set the same form edits an existing transaction instead of
/// recording a new one: fields arrive prefilled and saving rewrites the entry
/// in place, preserving its id, kind, and insertion timestamp. Deleting the
/// entry lives here too, bottom-left like the quick-set sheet's clear action,
/// so a recorded trade has one page for everything that can happen to it.
struct TradeEntryView: View {
    @Environment(AppState.self) private var appState
    let symbol: SymbolID
    private let recordSide: TradeSide
    /// The transaction being edited; nil in record mode.
    private let editing: PositionTransaction?
    let returnRoute: PositionReturnRoute
    @Binding var route: PopoverRoute

    @State private var priceText: String
    @State private var quantityText: String
    @State private var date: Date
    @State private var showsCalendar = false
    /// Daily candles backing the market-closed hint — whatever the detail
    /// chart already cached, or one fetch on first open.
    @State private var dailyCandles: [Candle] = []
    /// Return can reach `save()` twice in one keypress (field submit + default
    /// action); the first write wins so a trade is never recorded twice.
    @State private var didSave = false

    init(
        symbol: SymbolID,
        side: TradeSide,
        returnRoute: PositionReturnRoute,
        route: Binding<PopoverRoute>
    ) {
        self.symbol = symbol
        self.recordSide = side
        self.editing = nil
        self.returnRoute = returnRoute
        self._route = route
        _priceText = State(initialValue: "")
        _quantityText = State(initialValue: "")
        _date = State(initialValue: Self.marketToday(for: symbol.market))
    }

    init(
        symbol: SymbolID,
        editing transaction: PositionTransaction,
        returnRoute: PositionReturnRoute,
        route: Binding<PopoverRoute>
    ) {
        self.symbol = symbol
        self.recordSide = transaction.kind == .sell ? .sell : .buy
        self.editing = transaction
        self.returnRoute = returnRoute
        self._route = route
        _priceText = State(initialValue: Self.fieldText(transaction.price))
        _quantityText = State(initialValue: Self.fieldText(transaction.quantity))
        _date = State(initialValue: Calendar.current.startOfDay(for: transaction.date))
    }

    /// "Today" for this form is the market's own calendar date, not the
    /// user's. A US fill recorded from China at 1 a.m. belongs to the New York
    /// session still running, which is yesterday's date locally; dating it by
    /// the local clock would put the marker on a candle that doesn't exist
    /// yet and land it one day late once it does. The value is the local
    /// start-of-day instant for that calendar date, the form the ledger
    /// stores and `CandleTradeMarker` maps back through the local calendar.
    private static func marketToday(for market: Market) -> Date {
        var marketCalendar = Calendar(identifier: .gregorian)
        marketCalendar.timeZone = market.timeZone
        let components = marketCalendar.dateComponents([.year, .month, .day], from: .now)
        return Calendar.current.date(from: components) ?? Calendar.current.startOfDay(for: .now)
    }

    private var marketToday: Date { Self.marketToday(for: symbol.market) }

    private var item: WatchItem? { appState.watchlist.item(for: symbol) }
    private var quote: Quote? { appState.market.quote(for: symbol) }
    private var currencyCode: String? { quote?.currencyCode ?? symbol.currencyCode }

    /// The effective entry kind: the form's side in record mode, the stored
    /// kind (including adjustments) in edit mode.
    private var kind: PositionTransaction.Kind {
        editing?.kind ?? (recordSide == .buy ? .buy : .sell)
    }

    private var sideColor: Color {
        switch kind {
        case .buy: appState.palette.color(isUp: true)
        case .sell: appState.palette.color(isUp: false)
        case .adjustment: .secondary
        }
    }

    private var title: String {
        PulseLocalization.localizedString(
            editing != nil
                ? "trade.editTitle"
                : (recordSide == .buy ? "trade.buy" : "trade.sell")
        )
    }

    /// Where the page dismisses to: the trade log for edits, the hub for records.
    private var dismissRoute: PopoverRoute {
        editing != nil
            ? .transactions(symbol, returnRoute)
            : .position(symbol, returnRoute)
    }

    var body: some View {
        VStack(spacing: 0) {
            PositionPageHeader(
                symbol: symbol,
                title: (title, sideColor),
                onBack: { route = dismissRoute }
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PositionInputCell(
                        label: PulseLocalization.localizedString("trade.price"),
                        text: $priceText,
                        suggestion: currentPriceSuggestion,
                        autofocus: true
                    )
                    PositionInputCell(
                        label: PulseLocalization.localizedString("position.quantity"),
                        text: $quantityText,
                        suggestion: availableToSellSuggestion
                    )
                }
                dateRow
                if let closedDayHint {
                    Text(closedDayHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                preview
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .animation(.snappy(duration: 0.2), value: closedDayHint)

            Spacer(minLength: 0)
            HStack {
                if editing != nil {
                    // `.destructive` alone doesn't color a bordered macOS
                    // button; the label carries the red itself.
                    Button(role: .destructive) {
                        deleteEditedTransaction()
                    } label: {
                        Text(PulseLocalization.localizedString("action.delete"))
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Button(PulseLocalization.localizedString("action.cancel")) {
                    route = dismissRoute
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
        .task(id: symbol) { await loadDailyCandles() }
    }

    /// Reuses the detail chart's 250-bar daily cache when it's already warm;
    /// one fetch otherwise, so the closed-day hint can name the exact trading
    /// day a marker would snap to.
    private func loadDailyCandles() async {
        let key = CandleCacheKey(symbol: symbol, period: .day)
        if let cached = appState.market.cachedCandles(for: key, maxAge: .infinity) {
            dailyCandles = cached
            return
        }
        dailyCandles = await appState.engine.loadCandles(for: symbol, period: .day, count: 250)
    }

    // MARK: - Form rows

    /// The live price as a one-click fill. The chip follows the quote, but
    /// what lands in the field is the price at the moment of the click and
    /// stays put — a limit the user chose, not a number that keeps moving.
    private var currentPriceSuggestion: PositionInputCell.Suggestion? {
        guard let quote, quote.price.isFinite, quote.price > 0 else { return nil }
        let price = PriceFormatter.price(quote.price, market: symbol.market)
        return PositionInputCell.Suggestion(
            label: PulseLocalization.localizedString("trade.currentPrice", price),
            help: PulseLocalization.localizedString("trade.fillCurrentPriceHelp"),
            fill: { priceText = price }
        )
    }

    /// Selling against a long offers what's sellable. Shorts stay unadorned —
    /// negative quantities speak for themselves to anyone shorting. Edit mode
    /// drops the chip: the sellable count already includes the entry being
    /// edited, so offering it would double-count.
    private var availableToSellSuggestion: PositionInputCell.Suggestion? {
        guard editing == nil, kind == .sell, let item, item.positionQuantity > 0 else { return nil }
        let quantity = PriceFormatter.quantity(item.positionQuantity)
        return PositionInputCell.Suggestion(
            label: PulseLocalization.localizedString("trade.availableToSell", quantity),
            help: PulseLocalization.localizedString("trade.fillAvailableHelp"),
            fill: { quantityText = quantity }
        )
    }

    /// Resting state stays in the app's own chrome: arrows step ±1 day for
    /// the common "today/yesterday" records, and clicking the date opens a
    /// system calendar popover for anything older. Nothing can be dated past
    /// the market's current trading day.
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
                CalendarDatePicker(date: $date, maximumDate: marketToday)
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
        Calendar.current.isDate(date, inSameDayAs: marketToday)
    }

    /// "Today"/"Yesterday" count from the market's trading date (see
    /// `marketToday`), so the default date always reads as today even when
    /// the local clock has already rolled past midnight.
    private var dateLabel: String {
        let calendar = Calendar.current
        if isToday {
            return PulseLocalization.localizedString("trade.dateToday")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: marketToday),
           calendar.isDate(date, inSameDayAs: yesterday) {
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
        guard next <= marketToday else { return }
        date = next
    }

    /// A picked day with no session of its own — weekend, holiday, or the
    /// local day a late-session fill landed on. The record keeps the entered
    /// date; the hint only says where the chart marker will land. Adjustments
    /// never draw markers, so they never draw this hint either.
    ///
    /// Only a gap inside the loaded history counts as a closure. A day the
    /// candles don't reach — today while the session is still running and
    /// its bar isn't published, a stale cache, a future pick — tells us
    /// nothing, so it falls back to the weekend check rather than calling an
    /// open market closed.
    private var closedDayHint: String? {
        guard kind != .adjustment else { return nil }
        switch CandleTradeMarker.markerDay(for: date, candles: dailyCandles, market: symbol.market) {
        case .tradingDay:
            return nil
        case .closedDay(let candleDay):
            return PulseLocalization.localizedString(
                "trade.closedDay.snap",
                shortDayLabel(candleDay)
            )
        case .outsideHistory:
            guard isMarketWeekend(date) else { return nil }
            return PulseLocalization.localizedString("trade.closedDay")
        }
    }

    /// Saturday/Sunday in the market's own timezone. Crypto trades through
    /// weekends, so its "weekend" is never a closure.
    private func isMarketWeekend(_ day: Date) -> Bool {
        guard symbol.market != .crypto else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = symbol.market.timeZone
        let weekday = calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }

    /// The candle day in the market's timezone — the same label the chart's
    /// axis shows — in the compact form the date row uses.
    private func shortDayLabel(_ day: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = symbol.market.timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = PulseLocalization.currentLocale
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: .now)
        formatter.dateFormat = sameYear ? "MM-dd" : "yyyy-MM-dd"
        return formatter.string(from: day)
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
            ?? (kind == .sell ? held > 0 : kind == .buy ? held < 0 : false)
        let showsAverageCost = simulated.map { $0.quantity != 0 }
            ?? (kind == .sell ? held <= 0 : kind == .buy ? held >= 0 : held != 0)
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
            Text(PulseLocalization.localizedString(
                editing != nil
                    ? "action.save"
                    : (recordSide == .buy ? "trade.confirmBuy" : "trade.confirmSell")
            ))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .keyboardShortcut(.defaultAction)
        .help(PulseLocalization.localizedString(
            editing != nil
                ? "action.saveHelp"
                : (recordSide == .buy ? "trade.confirmBuyHelp" : "trade.confirmSellHelp")
        ))
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(sideColor.opacity(0.92))
        )
        .disabled(!isValid)
        .opacity(isValid ? 1 : 0.45)
    }

    // MARK: - Parsing & simulation

    /// An adjustment writes a target state, so zero is a legitimate input there
    /// ("flat, no cost"); real trades keep the strictly-positive contract.
    private var parsedPrice: Double? {
        parseDecimal(priceText).flatMap {
            $0.isFinite && (kind == .adjustment ? $0 >= 0 : $0 > 0) ? $0 : nil
        }
    }

    private var parsedQuantity: Double? {
        parseDecimal(quantityText).flatMap {
            $0.isFinite && (kind == .adjustment ? $0 >= 0 : $0 > 0) ? $0 : nil
        }
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
    /// store will on save) so the preview matches the post-save state. In edit
    /// mode the existing entry is replaced in the replay rather than appended.
    private var simulatedOutcome: SimulatedOutcome? {
        guard let item, let price = parsedPrice, let quantity = parsedQuantity else { return nil }
        var transactions = item.materializedTransactions()
        if let editing {
            guard let existing = transactions.firstIndex(where: { $0.id == editing.id }) else {
                return nil
            }
            var updated = editing
            updated.price = price
            updated.quantity = quantity
            updated.date = date
            transactions[existing] = updated
        } else {
            transactions.append(PositionTransaction(
                kind: recordSide == .buy ? .buy : .sell,
                price: price,
                quantity: quantity,
                date: date
            ))
        }
        let ledger = PositionLedger(transactions: transactions)
        let realized = editing.flatMap { target in
            ledger.entries.first { $0.transaction.id == target.id }?.realizedPnL
        } ?? ledger.entries.last?.realizedPnL
        return SimulatedOutcome(
            amount: price * quantity,
            realized: realized,
            quantity: ledger.quantity,
            averageCost: ledger.averageCost
        )
    }

    private func save() {
        guard !didSave, let item, let price = parsedPrice, let quantity = parsedQuantity, isValid else { return }
        didSave = true
        if var updated = editing {
            updated.price = price
            updated.quantity = quantity
            updated.date = date
            appState.watchlist.updateTransaction(item.symbol, updated)
        } else {
            appState.watchlist.addTransaction(item.symbol, PositionTransaction(
                kind: recordSide == .buy ? .buy : .sell,
                price: price,
                quantity: quantity,
                date: date
            ))
        }
        route = dismissRoute
    }

    /// Removes the entry being edited and returns to the log it came from —
    /// or straight to the hub when this was the last entry, since an empty
    /// log has nothing to show.
    private func deleteEditedTransaction() {
        guard !didSave, let editing else { return }
        didSave = true
        appState.watchlist.deleteTransaction(symbol, id: editing.id)
        let remaining = appState.watchlist.item(for: symbol)?.transactions ?? []
        route = remaining.isEmpty ? .position(symbol, returnRoute) : dismissRoute
    }

    private func parseDecimal(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    /// Field prefill that keeps full precision instead of the display rounding
    /// `PriceFormatter` applies — editing then saving without touching a field
    /// must never silently re-round a price.
    private static func fieldText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...10)).grouping(.never))
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
