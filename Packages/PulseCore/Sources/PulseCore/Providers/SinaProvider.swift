import Foundation

/// Sina Finance quotes and history (hq.sinajs.cn / stock2.finance.sina.com.cn, unofficial API).
///
/// Pulse uses it for the two things no other wired source can do: London spot
/// metals and the Shanghai contracts. Yahoo has never had a working spot symbol
/// (`XAUUSD=X`, `XAU=X` and `GCUSD=X` all 404) and covers no Chinese exchange;
/// Tencent's `hf_` channel serves international quotes but has no history
/// endpoint at all and does not carry `nf_` domestic futures.
///
/// Sina exposes the two channels differently:
///
/// - `hf_` (international): quotes share Tencent's payload (see
///   `InternationalFuturesQuote`); history is a daily series back to 2006 plus a
///   one-day minute line, and the other periods are resampled from those.
/// - `nf_` (domestic futures): its own quote payload, and native endpoints for
///   daily and 1/5/15/30/60-minute bars — only weekly and monthly are resampled.
public struct SinaProvider: QuoteProvider {
    public static let providerID = "sina"

    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: Self.providerID,
            name: PulseLocalization.localizedString("provider.sina"),
            markets: [.metal, .metalCN],
            capabilities: [.quotes, .candles],
            delay: [.metal: 0, .metalCN: 0],
            rateLimit: RateLimitPolicy(minInterval: 1, batchSize: 20),
            suggestedPollInterval: 15
        )
    }

    /// Sina's referer check rejects anonymous requests outright.
    private static let headers = ["Referer": "https://finance.sina.com.cn"]

    // MARK: - Symbol mapping

    /// Sina carries the metals on three channels, and the prefix decides both the
    /// payload shape and which history endpoints exist.
    enum Channel: String {
        /// International futures and London spot.
        case international = "hf_"
        /// Domestic (SHFE) futures.
        case domestic = "nf_"
        /// Shanghai Gold Exchange spot. Quotes only — Sina publishes no history
        /// for it, which is why the exchange's own daily file is wired up too.
        case shanghaiSpot = "gds_"
    }

    static func channel(for metal: PreciousMetalID) -> Channel {
        switch metal {
        case .shanghaiGoldSpot: .shanghaiSpot
        case .shanghaiGold, .shanghaiSilver: .domestic
        case .gold, .goldSpot, .silver, .silverSpot, .platinum, .palladium: .international
        }
    }

    /// The contract codes Sina publishes. The international ones match Tencent's,
    /// which is why one payload parser serves both.
    static func sinaContract(for metal: PreciousMetalID) -> String {
        switch metal {
        case .gold: "GC"
        case .goldSpot: "XAU"
        case .silver: "SI"
        case .silverSpot: "XAG"
        case .platinum: "XPT"
        case .palladium: "XPD"
        case .shanghaiGoldSpot: "AU9999"
        case .shanghaiGold: "AU0"
        case .shanghaiSilver: "AG0"
        }
    }

    static func sinaSymbol(for id: SymbolID) -> String? {
        id.metalID.map { channel(for: $0).rawValue + sinaContract(for: $0) }
    }

    // MARK: - QuoteProvider

    /// Sina exposes no search endpoint for this channel, and it does not need
    /// one: Pulse's own metal catalog owns discovery for everything Sina serves.
    public func search(_ query: String) async throws -> [SymbolInfo] {
        throw ProviderError.unsupported(.search)
    }

    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }
        let batchSize = descriptor.rateLimit?.batchSize ?? 20
        var quotes: [Quote] = []
        for chunk in symbols.chunked(into: batchSize) {
            let mapping = Dictionary(uniqueKeysWithValues: chunk.compactMap { symbol in
                Self.sinaSymbol(for: symbol).map { ($0, symbol) }
            })
            guard !mapping.isEmpty else { continue }
            let list = mapping.keys.sorted().joined(separator: ",")
            let url = URL(string: "https://hq.sinajs.cn/list=\(list)")!
            let data = try await http.get(url, headers: Self.headers)
            guard let text = data.decodedGB18030() ?? String(data: data, encoding: .utf8) else {
                throw ProviderError.badResponse("sina: undecodable response")
            }
            quotes += Self.parseQuotes(text: text, mapping: mapping)
        }
        guard !quotes.isEmpty else {
            // HTTP was already 200: an empty parse means Sina does not know these
            // symbols, which is a request problem rather than a source failure.
            throw ProviderError.clientError(status: 200, detail: "sina: no quotes parsed (unknown symbols?)")
        }
        return quotes
    }

    /// `var hq_str_hf_XAU="4490.41,4334.170,...,伦敦金（现货黄金）";`
    static func parseQuotes(text: String, mapping: [String: SymbolID]) -> [Quote] {
        var result: [Quote] = []
        for line in text.split(separator: ";") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.hasPrefix("var hq_str_"),
                  let symbol = mapping[String(key.dropFirst("var hq_str_".count))] else { continue }
            let payload = line[line.index(after: eq)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"\n\r "))
            let quote = switch symbol.metalID.map(channel(for:)) {
            case .domestic:
                parseDomesticQuote(payload: payload, symbol: symbol)
            case .shanghaiSpot:
                // Same 14-field shape as the international channel, except that
                // the open-interest slot carries traded volume here.
                InternationalFuturesQuote.parse(payload: payload, symbol: symbol, volumeField: 9)
            case .international, nil:
                InternationalFuturesQuote.parse(payload: payload, symbol: symbol)
            }
            guard let quote else { continue }
            result.append(quote)
        }
        return result
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard let metal = symbol.metalID else { throw ProviderError.unsupported(.candles) }
        // Sina quotes the Shanghai spot contract but publishes no history for it;
        // say so here rather than spending a request to find out.
        guard Self.channel(for: metal) != .shanghaiSpot else {
            throw ProviderError.unsupported(.candles)
        }
        let contract = Self.sinaContract(for: metal)

        // Domestic futures have a native endpoint per intraday resolution;
        // international ones publish a single minute line to resample. Weekly and
        // monthly always come from the daily series.
        let candles: [Candle]
        if Self.channel(for: metal) == .domestic {
            candles = if let minutes = period.intradayMinutes {
                try await domesticMinuteCandles(contract: contract, minutes: minutes)
            } else {
                Self.aggregate(try await domesticDailyCandles(contract: contract), into: period)
            }
        } else if period.isIntraday {
            candles = Self.aggregate(try await minuteCandles(contract: contract), into: period)
        } else {
            candles = Self.aggregate(try await dailyCandles(contract: contract), into: period)
        }
        guard !candles.isEmpty else {
            throw ProviderError.badResponse("sina: no candles parsed for \(contract)")
        }
        return Array(candles.suffix(count))
    }

    private func dailyCandles(contract: String) async throws -> [Candle] {
        let url = URL(string: "https://stock2.finance.sina.com.cn/futures/api/jsonp.php/x/"
            + "GlobalFuturesService.getGlobalFuturesDailyKLine?symbol=\(contract)")!
        let data = try await http.get(url, headers: Self.headers)
        return try Self.parseDailyCandles(Self.jsonPayload(from: data))
    }

    private func minuteCandles(contract: String) async throws -> [Candle] {
        let url = URL(string: "https://stock2.finance.sina.com.cn/futures/api/jsonp.php/x/"
            + "GlobalFuturesService.getGlobalFuturesMinLine?symbol=\(contract)")!
        let data = try await http.get(url, headers: Self.headers)
        return try Self.parseMinuteCandles(Self.jsonPayload(from: data))
    }

    private func domesticDailyCandles(contract: String) async throws -> [Candle] {
        let url = URL(string: "https://stock2.finance.sina.com.cn/futures/api/jsonp.php/x/"
            + "InnerFuturesNewService.getDailyKLine?symbol=\(contract)")!
        let data = try await http.get(url, headers: Self.headers)
        return try Self.parseDomesticCandles(Self.jsonPayload(from: data), dateFormat: "yyyy-MM-dd")
    }

    private func domesticMinuteCandles(contract: String, minutes: Int) async throws -> [Candle] {
        let url = URL(string: "https://stock2.finance.sina.com.cn/futures/api/jsonp.php/x/"
            + "InnerFuturesNewService.getFewMinLine?symbol=\(contract)&type=\(minutes)")!
        let data = try await http.get(url, headers: Self.headers)
        return try Self.parseDomesticCandles(
            Self.jsonPayload(from: data), dateFormat: "yyyy-MM-dd HH:mm:ss"
        )
    }

    // MARK: - Parsing

    /// `var hq_str_nf_AU0="黄金连续,023000,<open>,<high>,<low>,<prevClose>,<bid>,<ask>,
    ///  <last>,<settlement>,<prevSettlement>,<bidSize>,<askSize>,<openInterest>,
    ///  <volume>,<exchange>,<product>,<date>,…";`
    ///
    /// A futures day is measured against the previous settlement, not the previous
    /// close — the close field is reported as 0 on this channel.
    static func parseDomesticQuote(payload: String, symbol: SymbolID) -> Quote? {
        let f = payload.components(separatedBy: ",")
        guard f.count > 17, let price = Double(f[8]), price > 0 else { return nil }
        let reference = positive(f[10]) ?? positive(f[5]) ?? price
        let name = f[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return Quote(
            symbol: symbol,
            name: name.isEmpty ? nil : name,
            price: price,
            previousClose: reference,
            open: positive(f[2]),
            high: positive(f[3]),
            low: positive(f[4]),
            volume: positive(f[14]),
            currencyCode: symbol.currencyCode,
            timestamp: Self.domesticTimestamp(date: f[17], time: f[1]) ?? .now
        )
    }

    private static func positive(_ raw: String) -> Double? {
        Double(raw).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The domestic channel stamps its time as `HHmmss` alongside a separate date.
    static func domesticTimestamp(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Market.metalCN.timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.date(from: "\(date) \(time)")
    }

    private struct DomesticRow: Decodable {
        let d: String
        let o: String
        let h: String
        let l: String
        let c: String
        let v: String?
    }

    /// Domestic daily and minute bars share one row shape, differing only in
    /// whether `d` carries a time.
    static func parseDomesticCandles(_ data: Data, dateFormat: String) throws -> [Candle] {
        let rows: [DomesticRow]
        do {
            rows = try JSONDecoder().decode([DomesticRow].self, from: data)
        } catch {
            throw ProviderError.badResponse("sina domestic: \(error.localizedDescription)")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Market.metalCN.timeZone
        formatter.dateFormat = dateFormat
        return rows.compactMap { row in
            guard let time = formatter.date(from: row.d),
                  let open = Double(row.o), let high = Double(row.h),
                  let low = Double(row.l), let close = Double(row.c), close > 0 else { return nil }
            return Candle(
                time: time, open: open, high: high, low: low, close: close,
                volume: row.v.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
            )
        }
        .sorted { $0.time < $1.time }
    }

    /// Unwraps the JSONP callback. The body is also prefixed with an inline
    /// anti-hotlink `<script>` comment, so the payload starts at the first
    /// parenthesis rather than at the start of the response.
    static func jsonPayload(from data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) ?? data.decodedGB18030(),
              let start = text.firstIndex(of: "("),
              let end = text.lastIndex(of: ")"),
              start < end else {
            throw ProviderError.badResponse("sina: not a JSONP payload")
        }
        return Data(text[text.index(after: start)..<end].utf8)
    }

    private struct DailyRow: Decodable {
        let date: String
        let open: String
        let high: String
        let low: String
        let close: String
        let volume: String?
    }

    static func parseDailyCandles(_ data: Data) throws -> [Candle] {
        let rows: [DailyRow]
        do {
            rows = try JSONDecoder().decode([DailyRow].self, from: data)
        } catch {
            throw ProviderError.badResponse("sina daily: \(error.localizedDescription)")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = InternationalFuturesQuote.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return rows.compactMap { row in
            guard let time = formatter.date(from: row.date),
                  let open = Double(row.open), let high = Double(row.high),
                  let low = Double(row.low), let close = Double(row.close),
                  close > 0 else { return nil }
            // Spot has no exchange volume, and Sina reports 0 for the contracts
            // too; a zero would read as "no trading" rather than "not reported".
            let volume = row.volume.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
            return Candle(time: time, open: open, high: high, low: low, close: close, volume: volume)
        }
        .sorted { $0.time < $1.time }
    }

    /// `{"minLine_1d":[[<date>,<prevClose>,<exchange>,"",<hh:mm>,<price>,…,<datetime>],
    ///                 [<hh:mm>,<price>,…,<datetime>], …]}`
    /// The opening row carries extra leading fields, so both shapes are read from
    /// the end: the timestamp is always last and the price always fifth from last.
    static func parseMinuteCandles(_ data: Data) throws -> [Candle] {
        let decoded: [String: [[String]]]
        do {
            decoded = try JSONDecoder().decode([String: [[String]]].self, from: data)
        } catch {
            throw ProviderError.badResponse("sina minute: \(error.localizedDescription)")
        }
        guard let rows = decoded["minLine_1d"] else { return [] }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = InternationalFuturesQuote.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return rows.compactMap { row -> Candle? in
            guard row.count >= 5,
                  let time = formatter.date(from: row[row.count - 1]),
                  let price = Double(row[row.count - 5]), price > 0 else { return nil }
            // A minute line carries one price per minute, not a bar.
            return Candle(time: time, open: price, high: price, low: price, close: price)
        }
        .sorted { $0.time < $1.time }
    }

    /// Sina's series are Shanghai-anchored, whichever contract they describe:
    /// both its channels stamp Beijing time regardless of the venue.
    static func aggregate(_ candles: [Candle], into period: CandlePeriod) -> [Candle] {
        CandleResampler.resample(candles, into: period, timeZone: InternationalFuturesQuote.timeZone)
    }
}
