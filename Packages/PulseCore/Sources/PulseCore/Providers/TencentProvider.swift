import Foundation

/// Tencent quote snapshots (qt.gtimg.cn, unofficial API).
/// Capabilities: batch quotes plus real-time A-share minute series; other markets and historical K-line periods fall back to the next provider.
/// The response is GBK-encoded text of the form `v_sh600519="1~<name>~600519~<price>~<prevClose>~<open>~...";`.
public struct TencentProvider: QuoteProvider {
    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: "tencent",
            name: PulseLocalization.localizedString("provider.tencent"),
            markets: [.us, .hk, .sh, .sz],
            capabilities: [.quotes, .search, .candles],
            candleMarkets: [.sh, .sz],
            candlePeriods: [.minute1, .minute5],
            delay: [.us: 0, .hk: 900, .sh: 0, .sz: 0],
            rateLimit: RateLimitPolicy(minInterval: 2, batchSize: 60),
            suggestedPollInterval: 15
        )
    }

    // MARK: - Symbol mapping

    static func tencentSymbol(for id: SymbolID) -> String {
        switch id.market {
        case .us: "us" + id.code
        case .hk: "hk" + id.paddedCode(width: 5)
        case .sh: "sh" + id.code
        case .sz: "sz" + id.code
        case .crypto: id.code
        }
    }

    // MARK: - QuoteProvider

    public func search(_ query: String) async throws -> [SymbolInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let url = URL(string: "https://smartbox.gtimg.cn/s3/?v=2&q=\(encoded)&t=all")!
        let data = try await http.get(url, headers: ["Referer": "https://gu.qq.com/"])
        guard let text = data.decodedGB18030() ?? String(data: data, encoding: .utf8) else {
            throw ProviderError.badResponse("tencent smartbox: undecodable response")
        }
        return Self.parseSearch(text: text)
    }

    /// smartbox response: `v_hint="sh~000847~\\u817e...~txja~ZS^hk~00700~\\u817e...~txkg~GP^..."`
    /// Entries are separated by ^, fields by ~: [market, code, name (unicode-escaped), pinyin, type]
    static func parseSearch(text: String) -> [SymbolInfo] {
        guard let start = text.firstIndex(of: "\""),
              let end = text.lastIndex(of: "\""), start < end else { return [] }
        let body = text[text.index(after: start)..<end]
        var results: [SymbolInfo] = []
        for entry in body.split(separator: "^") {
            let f = entry.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5 else { continue }
            let market: Market? = switch f[0] {
            case "sh": .sh
            case "sz": .sz
            case "hk": .hk
            case "us": .us
            default: nil  // jj (OTC funds), bk (sectors), etc. are not supported yet
            }
            guard let market else { continue }

            // US codes carry an exchange suffix (aapl.oq / tme.n); take the part before the dot
            var code = f[1]
            if market == .us, let dot = code.firstIndex(of: ".") {
                code = String(code[..<dot])
            }

            let type: InstrumentType? = switch f[4].prefix(2).uppercased() {
            case "GP": .equity
            case "ZS": .index
            case "ET": .etf
            case "LO", "JJ": .fund
            default: nil
            }
            guard let type else { continue }

            let name = unescapeUnicode(f[2])
            guard !name.isEmpty else { continue }
            results.append(SymbolInfo(
                symbol: SymbolID(market: market, code: code),
                name: name,
                exchangeName: market.displayName,
                type: type
            ))
        }
        return results
    }

    /// smartbox returns Chinese names in \uXXXX escaped form
    static func unescapeUnicode(_ raw: String) -> String {
        guard raw.contains("\\u") else { return raw }
        return raw.applyingTransform(StringTransform("Hex-Any"), reverse: false) ?? raw
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard symbol.market.isChinaA, period.isIntraday else {
            throw ProviderError.unsupported(.candles)
        }

        let tencentSymbol = Self.tencentSymbol(for: symbol)
        var components = URLComponents(string: "https://web.ifzq.gtimg.cn/appstock/app/minute/query")!
        components.queryItems = [.init(name: "code", value: tencentSymbol)]
        let data = try await http.get(components.url!, headers: ["Referer": "https://gu.qq.com/"])
        let response: MinuteResponse
        do {
            response = try JSONDecoder().decode(MinuteResponse.self, from: data)
        } catch {
            throw ProviderError.badResponse("tencent minute: \(error.localizedDescription)")
        }
        guard response.code == 0,
              let minuteData = response.data?[tencentSymbol]?.data else {
            throw ProviderError.symbolNotFound(symbol)
        }
        let candles = Self.parseMinuteCandles(
            date: minuteData.date,
            rows: minuteData.data,
            market: symbol.market,
            period: period
        )
        guard !candles.isEmpty else {
            throw ProviderError.badResponse("tencent minute: no rows parsed")
        }
        return Array(candles.suffix(count))
    }

    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }
        let batchSize = descriptor.rateLimit?.batchSize ?? 60
        var quotes: [Quote] = []
        for chunk in symbols.chunked(into: batchSize) {
            let mapping = Dictionary(uniqueKeysWithValues: chunk.map { (Self.tencentSymbol(for: $0), $0) })
            let list = mapping.keys.sorted().joined(separator: ",")
            let url = URL(string: "https://qt.gtimg.cn/q=\(list)")!
            let data = try await http.get(url, headers: ["Referer": "https://gu.qq.com/"])
            guard let text = data.decodedGB18030() ?? String(data: data, encoding: .utf8) else {
                throw ProviderError.badResponse("tencent: undecodable response")
            }
            quotes += Self.parseQuotes(text: text, mapping: mapping)
        }
        guard !quotes.isEmpty else {
            // HTTP was already 200: failing to parse means a symbol problem (e.g. an instrument Tencent doesn't know), not a source failure
            throw ProviderError.clientError(status: 200, detail: "tencent: no quotes parsed (unknown symbols?)")
        }
        return quotes
    }

    // MARK: - Parsing

    /// Known field positions: 1 name, 3 last price, 4 previous close, 5 open, 30 timestamp, 31 change, 32 change %,
    /// 33 high, 34 low, 36 volume (in lots of 100 shares for A-shares), 37 turnover (in units of 10,000 CNY)
    static func parseQuotes(text: String, mapping: [String: SymbolID]) -> [Quote] {
        var result: [Quote] = []
        for line in text.split(separator: ";") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.hasPrefix("v_"), let symbol = mapping[String(key.dropFirst(2))] else { continue }
            let payload = line[line.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: "\"\n\r "))
            let f = payload.components(separatedBy: "~")
            guard f.count > 37,
                  let price = Double(f[3]), price > 0,
                  let prevClose = Double(f[4]) else { continue }

            let volumeRaw = Double(f[36]) ?? Double(f[6])
            let volumeMultiplier: Double = symbol.market.isChinaA ? 100 : 1  // A-share volume is reported in lots (100 shares)
            result.append(Quote(
                symbol: symbol,
                name: f[1].isEmpty ? nil : f[1],
                price: price,
                previousClose: prevClose,
                open: Double(f[5]),
                high: Double(f[33]),
                low: Double(f[34]),
                volume: volumeRaw.map { $0 * volumeMultiplier },
                turnover: Double(f[37]).map { $0 * 10_000 },
                currencyCode: symbol.market.currencyCode,
                timestamp: parseTimestamp(f[30], timeZone: symbol.market.timeZone) ?? .now
            ))
        }
        return result
    }

    /// Timestamp format varies by market: A-shares "20260703112400", HK/US "2026/07/03 11:24:00", etc. — all parsed in the exchange's time zone
    static func parseTimestamp(_ raw: String, timeZone: TimeZone) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formats = ["yyyyMMddHHmmss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    static func parseMinuteCandles(
        date: String,
        rows: [String],
        market: Market,
        period: CandlePeriod,
        now: Date = .now
    ) -> [Candle] {
        guard period.isIntraday else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = market.timeZone
        formatter.dateFormat = "yyyyMMdd HHmm"

        var minutes: [Candle] = []
        var previousCumulativeVolume = 0.0
        for row in rows {
            let fields = row.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 3,
                  let parsedTime = formatter.date(from: "\(date) \(fields[0])"),
                  let price = Double(fields[1]), price > 0,
                  let cumulativeVolume = Double(fields[2]) else { continue }
            // Tencent labels the in-progress point with the minute bucket's end (e.g. 10:44 at 10:43:24).
            // Keep its freshest price, but display that provisional point at the actual fetch time.
            let lead = parsedTime.timeIntervalSince(now)
            let time = lead > 0 && lead <= 60 ? now : parsedTime
            let incrementalLots = max(cumulativeVolume - previousCumulativeVolume, 0)
            previousCumulativeVolume = cumulativeVolume
            minutes.append(Candle(
                time: time,
                open: price,
                high: price,
                low: price,
                close: price,
                volume: incrementalLots * 100
            ))
        }

        guard period == .minute5 else { return minutes }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        let grouped = Dictionary(grouping: minutes) { candle in
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candle.time)
            let minute = (components.minute ?? 0) / 5 * 5
            return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(components.hour ?? 0)-\(minute)"
        }
        return grouped.values.compactMap { group -> Candle? in
            let sorted = group.sorted { $0.time < $1.time }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            return Candle(
                time: first.time,
                open: first.open,
                high: sorted.map(\.high).max() ?? first.high,
                low: sorted.map(\.low).min() ?? first.low,
                close: last.close,
                volume: sorted.compactMap(\.volume).reduce(0, +)
            )
        }
        .sorted { $0.time < $1.time }
    }
}

private struct MinuteResponse: Decodable {
    let code: Int
    let data: [String: SymbolPayload]?

    struct SymbolPayload: Decodable {
        let data: MinuteData
    }

    struct MinuteData: Decodable {
        let date: String
        let data: [String]
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
