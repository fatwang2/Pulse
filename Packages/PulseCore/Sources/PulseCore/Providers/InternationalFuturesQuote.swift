import Foundation

/// The `hf_` international-futures payload, which Tencent and Sina both serve in
/// the same 14 comma-separated fields:
///
/// `<price>,<field 1>,<bid>,<ask>,<high>,<low>,<time>,<prevClose>,<open>,
///  <openInterest>,<bidSize>,<askSize>,<date>,<name>`
///
/// Field 1 is the one place the two sources disagree — Tencent puts the change
/// percent there, Sina repeats the previous close — so nothing here reads it.
/// Change is derived from price and previous close anyway, the way every other
/// Pulse quote is.
///
/// Both sources stamp the date and time in Beijing time regardless of which
/// exchange the contract trades on, and neither carries traded volume.
enum InternationalFuturesQuote {
    /// Tencent and Sina both stamp this channel in Beijing time.
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    /// `volumeField` names the slot that carries traded volume when the channel
    /// reports it. The international feed puts open interest there instead, which
    /// is not volume and must not be shown as it.
    static func parse(payload: String, symbol: SymbolID, volumeField: Int? = nil) -> Quote? {
        let f = payload.components(separatedBy: ",")
        guard f.count > 13, let price = Double(f[0]), price > 0 else { return nil }
        // A closed session can report an empty or zero reference; the quote is
        // still true, it simply has no change to show against itself.
        let prevClose = Double(f[7]).flatMap { $0 > 0 ? $0 : nil } ?? price
        let name = f[13].trimmingCharacters(in: .whitespacesAndNewlines)
        return Quote(
            symbol: symbol,
            name: name.isEmpty ? nil : name,
            price: price,
            previousClose: prevClose,
            open: positive(f[8]),
            high: positive(f[4]),
            low: positive(f[5]),
            volume: volumeField.flatMap { $0 < f.count ? positive(f[$0]) : nil },
            currencyCode: symbol.currencyCode,
            timestamp: timestamp(date: f[12], time: f[6]) ?? .now
        )
    }

    private static func positive(_ raw: String) -> Double? {
        Double(raw).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func timestamp(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: "\(date) \(time)")
    }
}
