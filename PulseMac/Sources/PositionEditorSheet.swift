import SwiftUI
import PulseCore
import PulseUI

struct PositionEditorView: View {
    let item: WatchItem
    let quote: Quote?
    let palette: ChangePalette
    let onCancel: () -> Void
    let onSave: ([CostLot]) -> Void
    let onClear: () -> Void

    @State private var quantityText: String
    @State private var costText: String

    init(item: WatchItem, quote: Quote?, palette: ChangePalette,
         onCancel: @escaping () -> Void,
         onSave: @escaping ([CostLot]) -> Void, onClear: @escaping () -> Void) {
        self.item = item
        self.quote = quote
        self.palette = palette
        self.onCancel = onCancel
        self.onSave = onSave
        self.onClear = onClear
        _quantityText = State(initialValue: item.hasPosition ? PriceFormatter.quantity(item.positionQuantity) : "")
        _costText = State(initialValue: item.averageCost.map(PriceFormatter.price) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Form {
                TextField(PulseLocalization.localizedString("position.quantity"), text: $quantityText)
                TextField(PulseLocalization.localizedString("position.costPrice"), text: $costText)
            }
            .formStyle(.grouped)

            if let metrics {
                VStack(spacing: 6) {
                    previewRow(PulseLocalization.localizedString("position.marketValue"), PriceFormatter.money(metrics.marketValue, currencyCode: currencyCode))
                    previewRow(PulseLocalization.localizedString("metric.todayPnL"), PriceFormatter.signedMoney(metrics.todayPnL, currencyCode: currencyCode),
                               color: metrics.todayPnL)
                    previewRow(PulseLocalization.localizedString("metric.totalPnL"), "\(PriceFormatter.signedMoney(metrics.totalPnL, currencyCode: currencyCode)) · \(PriceFormatter.percent(metrics.totalReturnPercent))",
                               color: metrics.totalPnL)
                }
                .padding(.top, 2)
            }

            HStack {
                if item.hasPosition {
                    Button(PulseLocalization.localizedString("action.clearPosition"), role: .destructive) {
                        onClear()
                    }
                }
                Spacer()
                Button(PulseLocalization.localizedString("action.cancel")) {
                    onCancel()
                }
                Button(PulseLocalization.localizedString("action.save")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedQuantity == nil || parsedCost == nil)
            }
            .controlSize(.small)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PulseLocalization.localizedString("position.editTitle"))
                .font(.headline)
            HStack(spacing: 5) {
                Text(item.resolvedDisplayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(item.symbol.displayCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currencyCode: String? {
        quote?.currencyCode ?? item.symbol.currencyCode
    }

    private var parsedQuantity: Double? {
        parseDecimal(quantityText).flatMap { $0 > 0 ? $0 : nil }
    }

    private var parsedCost: Double? {
        parseDecimal(costText).flatMap { $0 > 0 ? $0 : nil }
    }

    private var metrics: PositionMetrics? {
        guard let quote, let quantity = parsedQuantity, let cost = parsedCost else { return nil }
        let draft = WatchItem(symbol: item.symbol, displayName: item.displayName,
                              addedAt: item.addedAt, lots: [CostLot(price: cost, quantity: quantity)])
        return PositionMetrics(item: draft, quote: quote)
    }

    private func previewRow(_ label: String, _ value: String, color: Double? = nil) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(color.map { palette.color(for: $0) } ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .font(.caption)
    }

    private func save() {
        guard let quantity = parsedQuantity, let cost = parsedCost else { return }
        onSave([CostLot(price: cost, quantity: quantity)])
    }

    private func parseDecimal(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }
}
