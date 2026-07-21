import Foundation

/// Command codes and message payloads for the Longbridge quote gateway.
/// Definitions mirror longbridge/openapi-protobufs (quote/api.proto + control commands);
/// only the subset Pulse needs is implemented.
enum LongbridgeCommand: UInt8 {
    case heartbeat = 1
    case auth = 2
    case reconnect = 3
    case querySecurityQuote = 11
    case queryIntraday = 18
    case queryCandlestick = 19
    case subscribe = 6
    case unsubscribe = 7
    case pushQuote = 101
}

enum LongbridgeMessages {
    // MARK: - Control

    /// message AuthRequest { string token = 1; map<string, string> metadata = 2; }
    /// A protobuf map entry is a nested message: { 1: key, 2: value }.
    static func authRequest(otp: String, metadata: [String: String] = [:]) -> Data {
        var writer = ProtobufWriter()
        writer.field(1, string: otp)
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            var entry = ProtobufWriter()
            entry.field(1, string: key)
            entry.field(2, string: value)
            writer.field(2, message: entry)
        }
        return writer.data
    }

    /// message AuthResponse { string session_id = 1; int64 expires = 2; }
    struct AuthResponse {
        var sessionID: String
        var expires: Int64

        init(decoding data: Data) throws {
            var sessionID = ""
            var expires: Int64 = 0
            var reader = ProtobufReader(data)
            while let field = try reader.nextField() {
                switch field.number {
                case 1: sessionID = field.value.string ?? ""
                case 2: expires = field.value.int ?? 0
                default: break
                }
            }
            self.sessionID = sessionID
            self.expires = expires
        }
    }

    /// message ReconnectRequest { string session_id = 1; map<string, string> metadata = 2; }
    static func reconnectRequest(sessionID: String, metadata: [String: String] = [:]) -> Data {
        var writer = ProtobufWriter()
        writer.field(1, string: sessionID)
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            var entry = ProtobufWriter()
            entry.field(1, string: key)
            entry.field(2, string: value)
            writer.field(2, message: entry)
        }
        return writer.data
    }

    /// Auth and reconnect return the same session payload.
    typealias ReconnectResponse = AuthResponse

    /// Server close push (cmd 0): code identifies the lifecycle reason and reason carries
    /// the actionable gateway detail (for example a connection-limit rejection).
    struct CloseNotice: Sendable, Equatable {
        enum Code: Int64, Sendable {
            case heartbeatTimeout = 0
            case serverError = 1
            case serverShutdown = 2
            case unpackError = 3
            case authError = 4
            case sessionExpired = 5
            case duplicateConnection = 6
        }

        var code: Code?
        var reason: String

        init(decoding data: Data) throws {
            var rawCode: Int64?
            var reason = ""
            var reader = ProtobufReader(data)
            while let field = try reader.nextField() {
                switch field.number {
                case 1: rawCode = field.value.int
                case 2: reason = field.value.string ?? ""
                default: break
                }
            }
            self.code = rawCode.flatMap(Code.init(rawValue:))
            self.reason = reason
        }
    }

    // MARK: - Quotes (cmd 11)

    /// message MultiSecurityRequest { repeated string symbol = 1; }
    static func multiSecurityRequest(symbols: [String]) -> Data {
        var writer = ProtobufWriter()
        for symbol in symbols {
            writer.field(1, string: symbol)
        }
        return writer.data
    }

    /// message PrePostQuote { last_done=1; timestamp=2; volume=3; turnover=4; high=5; low=6; prev_close=7 }
    struct PrePostQuote {
        var lastDone: Double?
        var timestamp: Int64 = 0
        var volume: Int64 = 0
        var turnover: Double?
        var high: Double?
        var low: Double?
        var prevClose: Double?

        init(decoding data: Data) throws {
            var reader = ProtobufReader(data)
            while let field = try reader.nextField() {
                switch field.number {
                case 1: lastDone = field.value.string.flatMap(Double.init)
                case 2: timestamp = field.value.int ?? 0
                case 3: volume = field.value.int ?? 0
                case 4: turnover = field.value.string.flatMap(Double.init)
                case 5: high = field.value.string.flatMap(Double.init)
                case 6: low = field.value.string.flatMap(Double.init)
                case 7: prevClose = field.value.string.flatMap(Double.init)
                default: break
                }
            }
        }
    }

    /// message SecurityQuote — see quote/api.proto
    struct SecurityQuote {
        var symbol = ""
        var lastDone: Double?
        var prevClose: Double?
        var open: Double?
        var high: Double?
        var low: Double?
        var timestamp: Int64 = 0
        var volume: Int64 = 0
        var turnover: Double?
        var tradeStatus: Int64 = 0
        var preMarket: PrePostQuote?
        var postMarket: PrePostQuote?
        var overnight: PrePostQuote?

        init(decoding data: Data) throws {
            var reader = ProtobufReader(data)
            while let field = try reader.nextField() {
                switch field.number {
                case 1: symbol = field.value.string ?? ""
                case 2: lastDone = field.value.string.flatMap(Double.init)
                case 3: prevClose = field.value.string.flatMap(Double.init)
                case 4: open = field.value.string.flatMap(Double.init)
                case 5: high = field.value.string.flatMap(Double.init)
                case 6: low = field.value.string.flatMap(Double.init)
                case 7: timestamp = field.value.int ?? 0
                case 8: volume = field.value.int ?? 0
                case 9: turnover = field.value.string.flatMap(Double.init)
                case 10: tradeStatus = field.value.int ?? 0
                case 11: preMarket = try field.value.data.map { try PrePostQuote(decoding: $0) }
                case 12: postMarket = try field.value.data.map { try PrePostQuote(decoding: $0) }
                case 13: overnight = try field.value.data.map { try PrePostQuote(decoding: $0) }
                default: break
                }
            }
        }
    }

    /// message SecurityQuoteResponse { repeated SecurityQuote secu_quote = 1; }
    static func decodeSecurityQuoteResponse(_ data: Data) throws -> [SecurityQuote] {
        var quotes: [SecurityQuote] = []
        var reader = ProtobufReader(data)
        while let field = try reader.nextField() {
            if field.number == 1, let payload = field.value.data {
                quotes.append(try SecurityQuote(decoding: payload))
            }
        }
        return quotes
    }

    // MARK: - Candlesticks (cmd 19)

    /// enum Period — raw values shared with the wire format
    enum Period: UInt64 {
        case minute1 = 1
        case minute5 = 5
        case day = 1000
        case week = 2000
        case month = 3000

        init?(_ period: CandlePeriod) {
            switch period {
            case .minute1: self = .minute1
            case .minute5: self = .minute5
            case .day: self = .day
            case .week: self = .week
            case .month: self = .month
            }
        }
    }

    /// message SecurityCandlestickRequest { symbol=1; period=2; count=3; adjust_type=4; trade_session=5 }
    static func candlestickRequest(symbol: String, period: Period, count: Int) -> Data {
        var writer = ProtobufWriter()
        writer.field(1, string: symbol)
        writer.field(2, varint: period.rawValue)
        writer.field(3, varint: UInt64(count))
        // adjust_type: NO_ADJUST(0), trade_session: NORMAL_TRADE(0) — proto3 zero fields are omitted
        return writer.data
    }

    /// message Candlestick { close=1; open=2; low=3; high=4; volume=5; turnover=6; timestamp=7; trade_session=8 }
    struct WireCandlestick {
        var close: Double?
        var open: Double?
        var low: Double?
        var high: Double?
        var volume: Int64 = 0
        var timestamp: Int64 = 0

        init(decoding data: Data) throws {
            var reader = ProtobufReader(data)
            while let field = try reader.nextField() {
                switch field.number {
                case 1: close = field.value.string.flatMap(Double.init)
                case 2: open = field.value.string.flatMap(Double.init)
                case 3: low = field.value.string.flatMap(Double.init)
                case 4: high = field.value.string.flatMap(Double.init)
                case 5: volume = field.value.int ?? 0
                case 7: timestamp = field.value.int ?? 0
                default: break
                }
            }
        }

        var candle: Candle? {
            guard let close, let open, let low, let high, timestamp > 0 else { return nil }
            return Candle(
                time: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                open: open, high: high, low: low, close: close,
                volume: Double(volume)
            )
        }
    }

    /// message SecurityCandlestickResponse { symbol=1; repeated Candlestick candlesticks=2 }
    static func decodeCandlestickResponse(_ data: Data) throws -> [Candle] {
        var candles: [Candle] = []
        var reader = ProtobufReader(data)
        while let field = try reader.nextField() {
            if field.number == 2, let payload = field.value.data,
               let candle = try WireCandlestick(decoding: payload).candle {
                candles.append(candle)
            }
        }
        return candles
    }

    // MARK: - Subscription (cmd 6/7) and push (cmd 101)

    /// message SubscribeRequest { repeated string symbol=1; repeated SubType sub_type=2; bool is_first_push=3 }
    /// SubType.QUOTE = 1
    static func subscribeQuoteRequest(symbols: [String]) -> Data {
        var writer = ProtobufWriter()
        for symbol in symbols {
            writer.field(1, string: symbol)
        }
        writer.field(2, varint: 1) // QUOTE
        writer.field(3, varint: 1) // is_first_push: deliver a snapshot immediately
        return writer.data
    }

    /// message UnsubscribeRequest { repeated string symbol=1; repeated SubType sub_type=2; bool unsub_all=3 }
    static func unsubscribeQuoteRequest(symbols: [String]) -> Data {
        var writer = ProtobufWriter()
        for symbol in symbols {
            writer.field(1, string: symbol)
        }
        writer.field(2, varint: 1) // QUOTE
        return writer.data
    }

    /// message PushQuote — see quote/api.proto (trade_session: 0 normal, 1 pre, 2 post, 3 overnight)
    struct PushQuote {
        var symbol = ""
        var lastDone: Double?
        var open: Double?
        var high: Double?
        var low: Double?
        var timestamp: Int64 = 0
        var volume: Int64 = 0
        var turnover: Double?
        var tradeSession: Int64 = 0

        init(decoding data: Data) throws {
            var reader = ProtobufReader(data)
            while let field = try reader.nextField() {
                switch field.number {
                case 1: symbol = field.value.string ?? ""
                case 3: lastDone = field.value.string.flatMap(Double.init)
                case 4: open = field.value.string.flatMap(Double.init)
                case 5: high = field.value.string.flatMap(Double.init)
                case 6: low = field.value.string.flatMap(Double.init)
                case 7: timestamp = field.value.int ?? 0
                case 8: volume = field.value.int ?? 0
                case 9: turnover = field.value.string.flatMap(Double.init)
                case 11: tradeSession = field.value.int ?? 0
                default: break
                }
            }
        }

        var marketState: MarketState {
            switch tradeSession {
            case 1: .preMarket
            case 2: .postMarket
            case 3: .overnight
            default: .regular
            }
        }
    }

    // MARK: - Intraday (cmd 18)

    /// message SecurityIntradayRequest { symbol=1; trade_session=2 }
    static func intradayRequest(symbol: String) -> Data {
        var writer = ProtobufWriter()
        writer.field(1, string: symbol)
        return writer.data
    }

    /// message Line { price=1; timestamp=2; volume=3; turnover=4; avg_price=5 }
    /// message SecurityIntradayResponse { symbol=1; repeated Line lines=2 }
    static func decodeIntradayResponse(_ data: Data) throws -> [(time: Date, price: Double, volume: Int64)] {
        var lines: [(Date, Double, Int64)] = []
        var reader = ProtobufReader(data)
        while let field = try reader.nextField() {
            guard field.number == 2, let payload = field.value.data else { continue }
            var price: Double?
            var timestamp: Int64 = 0
            var volume: Int64 = 0
            var lineReader = ProtobufReader(payload)
            while let lineField = try lineReader.nextField() {
                switch lineField.number {
                case 1: price = lineField.value.string.flatMap(Double.init)
                case 2: timestamp = lineField.value.int ?? 0
                case 3: volume = lineField.value.int ?? 0
                default: break
                }
            }
            if let price, timestamp > 0 {
                lines.append((Date(timeIntervalSince1970: TimeInterval(timestamp)), price, volume))
            }
        }
        return lines
    }
}
