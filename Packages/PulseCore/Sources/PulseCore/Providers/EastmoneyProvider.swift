import Foundation

/// Eastmoney intraday history (push2his.eastmoney.com, unofficial API).
///
/// Wired for exactly one gap: the Shanghai Gold Exchange's Au99.99 has no
/// intraday history anywhere else. Sina quotes it but publishes no series, and
/// the exchange's own intraday file serves the previous session.
///
/// Eastmoney bans an IP for hours after a burst of requests — measured, not
/// assumed — so this provider deliberately declares **charts only**. That keeps
/// it out of quote polling entirely: it is asked for data when a chart opens or
/// a sparkline refreshes on its five-minute timer, and never on the quote tick.
/// If it does get blocked, the circuit breaker parks it and the daily history
/// from the exchange still draws.
public struct EastmoneyProvider: QuoteProvider {
    public static let providerID = "eastmoney"

    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: Self.providerID,
            name: PulseLocalization.localizedString("provider.eastmoney"),
            markets: [.metalCN],
            capabilities: [.candles],
            candleMarkets: [.metalCN],
            candlePeriods: [.minute1, .minute5, .minute15, .minute30, .hour1],
            delay: [.metalCN: 0],
            // Deliberately slow: this source answers charts, and pacing it is
            // what keeps it available at all.
            rateLimit: RateLimitPolicy(minInterval: 3)
        )
    }

    /// Eastmoney addresses everything as `<market>.<code>`; 118 is the Shanghai
    /// Gold Exchange.
    static func secid(for metal: PreciousMetalID) -> String? {
        switch metal {
        case .shanghaiGoldSpot: "118.AU9999"
        case .gold, .goldSpot, .silver, .silverSpot, .platinum, .palladium,
             .shanghaiGold, .shanghaiSilver: nil
        }
    }

    /// `klt` is Eastmoney's period code.
    static func klt(for period: CandlePeriod) -> Int? {
        switch period {
        case .minute1: 1
        case .minute5: 5
        case .minute15: 15
        case .minute30: 30
        case .hour1: 60
        case .day: 101
        case .week: 102
        case .month: 103
        }
    }

    // MARK: - QuoteProvider

    public func search(_ query: String) async throws -> [SymbolInfo] {
        throw ProviderError.unsupported(.search)
    }

    /// Charts only — see the note on this type.
    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        throw ProviderError.unsupported(.quotes)
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard let metal = symbol.metalID,
              let secid = Self.secid(for: metal),
              let klt = Self.klt(for: period) else {
            throw ProviderError.unsupported(.candles)
        }

        var components = URLComponents(string: "https://push2his.eastmoney.com/api/qt/stock/kline/get")!
        components.queryItems = [
            .init(name: "secid", value: secid),
            .init(name: "klt", value: String(klt)),
            .init(name: "fqt", value: "0"),
            .init(name: "beg", value: "0"),
            .init(name: "end", value: "20500101"),
            .init(name: "lmt", value: String(max(count, 1))),
            .init(name: "fields1", value: "f1,f2"),
            .init(name: "fields2", value: "f51,f52,f53,f54,f55,f56"),
        ]
        let data = try await http.get(
            components.url!,
            headers: ["Referer": "https://quote.eastmoney.com/"]
        )
        // A blocked request answers 200 with an empty body rather than an error.
        guard !data.isEmpty else {
            throw ProviderError.rateLimited
        }

        let candles = try Self.parseCandles(data, intraday: period.isIntraday)
        guard !candles.isEmpty else {
            throw ProviderError.badResponse("eastmoney: no candles parsed for \(secid)")
        }
        return Array(candles.suffix(count))
    }

    // MARK: - Parsing

    /// `{"data":{"klines":["2026-08-20 09:30,971.81,972.00,972.00,971.81,20", …]}}`
    /// where the fields are time, open, **close**, high, low, volume — Eastmoney
    /// puts close second, which is not the order the rest of the app uses.
    static func parseCandles(_ data: Data, intraday: Bool) throws -> [Candle] {
        struct Response: Decodable {
            struct Payload: Decodable { let klines: [String]? }
            let data: Payload?
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProviderError.badResponse("eastmoney: \(error.localizedDescription)")
        }
        guard let rows = response.data?.klines else { return [] }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Market.metalCN.timeZone
        formatter.dateFormat = intraday ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"

        return rows.compactMap { row -> Candle? in
            let f = row.components(separatedBy: ",")
            guard f.count >= 6,
                  let time = formatter.date(from: f[0]),
                  let open = Double(f[1]), let close = Double(f[2]),
                  let high = Double(f[3]), let low = Double(f[4]),
                  close > 0 else { return nil }
            return Candle(
                time: time, open: open, high: high, low: low, close: close,
                volume: Double(f[5]).flatMap { $0 > 0 ? $0 : nil }
            )
        }
        .sorted { $0.time < $1.time }
    }
}
