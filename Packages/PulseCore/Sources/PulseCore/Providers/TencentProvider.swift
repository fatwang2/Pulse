import Foundation

/// Tencent quote snapshots (qt.gtimg.cn, unofficial API).
/// Capabilities: batch quotes (up to a few dozen symbols per request); real-time for China A-shares, making it the preferred source for intraday prices.
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
            capabilities: [.quotes, .search],
            delay: [.us: 0, .hk: 900, .sh: 0, .sz: 0],
            rateLimit: RateLimitPolicy(minInterval: 2, batchSize: 60)
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
        throw ProviderError.unsupported(.candles)
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
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
