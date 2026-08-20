import Foundation

/// The Shanghai Gold Exchange's own daily history (sge.com.cn).
///
/// Au99.99 is the fully-paid spot contract Chinese gold ETFs benchmark against
/// and the price most people in China mean by "黄金", but no wired source
/// publishes history for it: Sina quotes it without a chart, and Yahoo covers no
/// Chinese exchange. The exchange itself does — one request returns every daily
/// bar back to 2016 — so Pulse takes the official file rather than depending on
/// a portal for the one series that matters most here.
///
/// Daily only. The exchange's intraday endpoint serves the *previous* session,
/// which would draw yesterday's line under today's date.
public struct ShanghaiGoldExchangeProvider: QuoteProvider {
    public static let providerID = "sge"

    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: Self.providerID,
            name: PulseLocalization.localizedString("provider.sge"),
            markets: [.metalCN],
            capabilities: [.candles],
            candleMarkets: [.metalCN],
            candlePeriods: [.day, .week, .month],
            delay: [.metalCN: 0],
            rateLimit: RateLimitPolicy(minInterval: 2)
        )
    }

    /// The exchange's instrument names, as its own endpoint spells them.
    static func instrumentID(for metal: PreciousMetalID) -> String? {
        switch metal {
        case .shanghaiGoldSpot: "Au99.99"
        case .gold, .goldSpot, .silver, .silverSpot, .platinum, .palladium,
             .shanghaiGold, .shanghaiSilver: nil
        }
    }

    // MARK: - QuoteProvider

    public func search(_ query: String) async throws -> [SymbolInfo] {
        throw ProviderError.unsupported(.search)
    }

    /// The exchange publishes history here, not live prices; quotes stay with Sina.
    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        throw ProviderError.unsupported(.quotes)
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard let metal = symbol.metalID,
              let instrument = Self.instrumentID(for: metal) else {
            throw ProviderError.unsupported(.candles)
        }
        guard !period.isIntraday else { throw ProviderError.unsupported(.candles) }

        let data = try await http.post(
            URL(string: "https://www.sge.com.cn/graph/Dailyhq")!,
            form: ["instid": instrument],
            headers: ["Referer": "https://www.sge.com.cn/"]
        )

        let daily = try Self.parseDailyCandles(data)
        let candles = SinaProvider.aggregate(daily, into: period)
        guard !candles.isEmpty else {
            throw ProviderError.badResponse("sge: no candles parsed for \(instrument)")
        }
        return Array(candles.suffix(count))
    }

    // MARK: - Parsing

    /// `{"time":[["2026-08-19", <open>, <close>, <low>, <high>], …]}`
    ///
    /// Note the order: close comes second and the extremes last, which is not the
    /// OHLC most feeds use. Volume is not published on this endpoint.
    static func parseDailyCandles(_ data: Data) throws -> [Candle] {
        struct Response: Decodable { let time: [[SGEValue]] }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProviderError.badResponse("sge daily: \(error.localizedDescription)")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Market.metalCN.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return response.time.compactMap { row -> Candle? in
            guard row.count >= 5,
                  let day = row[0].text, let time = formatter.date(from: day),
                  let open = row[1].number, let close = row[2].number,
                  let low = row[3].number, let high = row[4].number,
                  close > 0 else { return nil }
            return Candle(time: time, open: open, high: high, low: low, close: close)
        }
        .sorted { $0.time < $1.time }
    }

    /// Each row mixes the date string with four numbers.
    struct SGEValue: Decodable {
        let text: String?
        let number: Double?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                number = value
                text = nil
            } else {
                text = try? container.decode(String.self)
                number = nil
            }
        }
    }
}
