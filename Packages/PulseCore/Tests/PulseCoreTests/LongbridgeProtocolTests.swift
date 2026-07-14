import Foundation
import Testing
@testable import PulseCore

@Suite("Longbridge protocol")
struct LongbridgeProtocolTests {
    // MARK: - Protobuf codec

    @Test func protobufRoundTrip() throws {
        var writer = ProtobufWriter()
        writer.field(1, string: "700.HK")
        writer.field(2, varint: 1000)
        writer.field(7, int: 1_700_000_000)

        var reader = ProtobufReader(writer.data)
        var seen: [Int: ProtobufReader.Value] = [:]
        while let field = try reader.nextField() {
            seen[field.number] = field.value
        }
        #expect(seen[1]?.string == "700.HK")
        #expect(seen[2]?.uint == 1000)
        #expect(seen[7]?.int == 1_700_000_000)
    }

    @Test func protobufSkipsZeroFieldsLikeProto3() {
        var writer = ProtobufWriter()
        writer.field(1, varint: 0)
        writer.field(2, string: "")
        #expect(writer.data.isEmpty)
    }

    @Test func protobufMultiByteVarint() throws {
        var writer = ProtobufWriter()
        writer.field(3, varint: 300) // classic two-byte varint: 0xAC 0x02
        var reader = ProtobufReader(writer.data)
        let field = try #require(try reader.nextField())
        #expect(field.number == 3)
        #expect(field.value.uint == 300)
    }

    @Test func protobufRejectsTruncatedPayload() {
        var writer = ProtobufWriter()
        writer.field(1, string: "hello")
        let truncated = writer.data.dropLast(2)
        var reader = ProtobufReader(Data(truncated))
        #expect(throws: ProtobufDecodingError.self) {
            while try reader.nextField() != nil {}
        }
    }

    // MARK: - Packet framing

    @Test func requestFrameLayout() {
        let body = Data([0xDE, 0xAD])
        let frame = LongbridgePacket.encodeRequest(command: 11, requestID: 0x0102_0304, body: body, timeoutMS: 10_000)
        #expect(Array(frame) == [
            0x01,                     // type=1 in the low nibble, verify=0, gzip=0
            11,                       // cmd
            0x01, 0x02, 0x03, 0x04,   // request id (BE)
            0x27, 0x10,               // timeout 10000ms (BE)
            0x00, 0x00, 0x02,         // body_len u24
            0xDE, 0xAD,
        ])
    }

    @Test func matchesOfficialGoReferenceVector() {
        // Golden vector from openapi-protocol/go/v1/header_test.go, "pack request should ok":
        // Header{Type: 1, CmdCode: 1, RequestId: 1, Timeout: 0xff, BodyLength: 7}
        let frame = LongbridgePacket.encodeRequest(command: 1, requestID: 1, body: Data(count: 7), timeoutMS: 0xFF)
        #expect(Array(frame.prefix(11)) == [0b0000_0001, 0b0000_0001, 0, 0, 0, 1, 0, 0xFF, 0, 0, 7])
    }

    @Test func rejectsVerifiedPackets() {
        // Response frame with verify=1 gzip=1 (0b00110010) from the Go reference tests:
        // signed packets are not part of the OpenAPI quote gateway contract.
        var frame = Data([0b0011_0010, 1, 0, 0, 0, 1, 8, 0, 0, 7])
        frame.append(Data(count: 7))
        #expect(throws: LongbridgePacket.FramingError.self) {
            _ = try LongbridgePacket.decode(frame)
        }
    }

    @Test func decodesResponseFrame() throws {
        var body = ProtobufWriter()
        body.field(1, string: "session-1")
        var frame = Data([0x02, 2]) // type=2, cmd=auth
        frame.append(contentsOf: [0, 0, 0, 1]) // request id 1
        frame.append(0) // status success
        let payload = body.data
        frame.append(contentsOf: [0, 0, UInt8(payload.count)])
        frame.append(payload)

        let packets = try LongbridgePacket.decode(frame)
        #expect(packets.count == 1)
        guard case .response(let response) = try #require(packets.first) else {
            Issue.record("expected response packet")
            return
        }
        #expect(response.command == 2)
        #expect(response.requestID == 1)
        #expect(response.status == 0)
        let auth = try LongbridgeMessages.AuthResponse(decoding: response.body)
        #expect(auth.sessionID == "session-1")
    }

    @Test func decodesServerHeartbeatRequestAndPush() throws {
        // Server-initiated heartbeat: type=1 frame that the client must echo back.
        var frame = Data([0x01, 1])
        frame.append(contentsOf: [0, 0, 0, 9])       // request id 9
        frame.append(contentsOf: [0x00, 0x64])       // timeout
        frame.append(contentsOf: [0, 0, 1, 0x2A])    // 1-byte body
        // Push packet in the same websocket message.
        frame.append(contentsOf: [0x03, 101, 0, 0, 0])

        let packets = try LongbridgePacket.decode(frame)
        #expect(packets.count == 2)
        guard case .serverRequest(let command, let requestID, let body) = packets[0] else {
            Issue.record("expected server request")
            return
        }
        #expect(command == 1)
        #expect(requestID == 9)
        #expect(body == Data([0x2A]))
        guard case .push(let push) = packets[1] else {
            Issue.record("expected push")
            return
        }
        #expect(push.command == 101)
        #expect(push.body.isEmpty)
    }

    @Test func rejectsTruncatedFrame() {
        let frame = Data([0x02, 2, 0, 0]) // response header cut short
        #expect(throws: LongbridgePacket.FramingError.self) {
            _ = try LongbridgePacket.decode(frame)
        }
    }

    // MARK: - Quote payload decoding

    @Test func decodesSecurityQuoteResponse() throws {
        var pre = ProtobufWriter()
        pre.field(1, string: "184.20")
        pre.field(2, int: 1_700_000_100)
        pre.field(7, string: "183.50")

        var quote = ProtobufWriter()
        quote.field(1, string: "AAPL.US")
        quote.field(2, string: "183.50")
        quote.field(3, string: "181.00")
        quote.field(4, string: "182.10")
        quote.field(7, int: 1_700_000_000)
        quote.field(8, int: 52_000_000)
        quote.field(9, string: "9500000000")
        quote.field(11, message: pre)

        var envelope = ProtobufWriter()
        envelope.field(1, message: quote)

        let quotes = try LongbridgeMessages.decodeSecurityQuoteResponse(envelope.data)
        #expect(quotes.count == 1)
        let wire = try #require(quotes.first)
        #expect(wire.symbol == "AAPL.US")
        #expect(wire.lastDone == 183.50)
        #expect(wire.prevClose == 181.00)
        #expect(wire.open == 182.10)
        #expect(wire.volume == 52_000_000)
        #expect(wire.turnover == 9_500_000_000)
        #expect(wire.preMarket?.lastDone == 184.20)
        #expect(wire.preMarket?.prevClose == 183.50)
    }

    @Test func decodesCandlestickResponse() throws {
        var bar = ProtobufWriter()
        bar.field(1, string: "456.8")   // close
        bar.field(2, string: "455.0")   // open
        bar.field(3, string: "454.2")   // low
        bar.field(4, string: "457.6")   // high
        bar.field(5, int: 1_234_567)
        bar.field(7, int: 1_700_000_000)

        var envelope = ProtobufWriter()
        envelope.field(1, string: "700.HK")
        envelope.field(2, message: bar)

        let candles = try LongbridgeMessages.decodeCandlestickResponse(envelope.data)
        #expect(candles.count == 1)
        let candle = try #require(candles.first)
        #expect(candle.close == 456.8)
        #expect(candle.open == 455.0)
        #expect(candle.low == 454.2)
        #expect(candle.high == 457.6)
        #expect(candle.volume == 1_234_567)
        #expect(candle.time == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func encodesAuthMetadataAsProtobufMap() throws {
        let body = LongbridgeMessages.authRequest(otp: "otp-1", metadata: ["need_over_night_quote": "true"])
        var reader = ProtobufReader(body)
        var token = ""
        var entries: [String: String] = [:]
        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                token = field.value.string ?? ""
            case 2:
                var key = "", value = ""
                var entry = ProtobufReader(try #require(field.value.data))
                while let kv = try entry.nextField() {
                    if kv.number == 1 { key = kv.value.string ?? "" }
                    if kv.number == 2 { value = kv.value.string ?? "" }
                }
                entries[key] = value
            default: break
            }
        }
        #expect(token == "otp-1")
        #expect(entries == ["need_over_night_quote": "true"])
    }

    @Test func encodesSubscribeAndDecodesPushQuote() throws {
        // Subscribe payload round-trips through the codec with QUOTE type and first-push flag.
        var reader = ProtobufReader(LongbridgeMessages.subscribeQuoteRequest(symbols: ["700.HK", "AAPL.US"]))
        var symbols: [String] = []
        var subTypes: [UInt64] = []
        var firstPush: UInt64 = 0
        while let field = try reader.nextField() {
            switch field.number {
            case 1: symbols.append(field.value.string ?? "")
            case 2: subTypes.append(field.value.uint ?? 0)
            case 3: firstPush = field.value.uint ?? 0
            default: break
            }
        }
        #expect(symbols == ["700.HK", "AAPL.US"])
        #expect(subTypes == [1])
        #expect(firstPush == 1)

        // PushQuote decode, including the overnight session mapping.
        var push = ProtobufWriter()
        push.field(1, string: "AAPL.US")
        push.field(3, string: "212.44")
        push.field(7, int: 1_752_400_000)
        push.field(8, int: 1_000)
        push.field(11, varint: 3) // OVERNIGHT_TRADE
        let decoded = try LongbridgeMessages.PushQuote(decoding: push.data)
        #expect(decoded.symbol == "AAPL.US")
        #expect(decoded.lastDone == 212.44)
        #expect(decoded.timestamp == 1_752_400_000)
        #expect(decoded.marketState == .overnight)
    }

    // MARK: - Gzip

    @Test func gunzipInflatesGzipStream() throws {
        // gzip of "pulse" produced by `printf pulse | gzip`
        let gzipped = Data([
            0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03,
            0x2B, 0x28, 0xCD, 0x29, 0x4E, 0x05, 0x00,
            0x21, 0x4E, 0x16, 0x9F, 0x05, 0x00, 0x00, 0x00,
        ])
        let inflated = try LongbridgePacket.gunzip(gzipped)
        #expect(String(data: inflated, encoding: .utf8) == "pulse")
    }

    // MARK: - HTTP signature

    @Test func signatureMatchesOfficialAlgorithm() {
        // Golden vector computed with an independent implementation of
        // openapi/rust/crates/httpclient/src/signature.rs
        let credentials = LongbridgeCredentials(appKey: "test-key", appSecret: "test-secret", accessToken: "test-token")
        let signature = LongbridgeHTTP.signature(
            method: "GET", path: "/v1/socket/token", query: "",
            credentials: credentials, timestamp: "1700000000", body: nil
        )
        #expect(signature == "HMAC-SHA256 SignedHeaders=authorization;x-api-key;x-timestamp, Signature=493263838237cabe767d080e56a492ce14b568066f7c54898f1e94b162cc47dd")
    }

    // MARK: - Symbol and quote mapping

    @Test func mapsSymbolsToLongbridgeFormat() {
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .hk, code: "700")) == "700.HK")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .us, code: "AAPL")) == "AAPL.US")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .sh, code: "603986")) == "603986.SH")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .sz, code: "300750")) == "300750.SZ")
        #expect(LongbridgeProvider.longbridgeSymbol(for: SymbolID(market: .crypto, code: "BTC-USD")) == nil)
    }

    @Test func mapsWireQuoteToQuote() throws {
        var wireData = ProtobufWriter()
        wireData.field(1, string: "603986.SH")
        wireData.field(2, string: "562.00")
        wireData.field(3, string: "611.00")
        wireData.field(7, int: 1_700_000_000)
        let wire = try LongbridgeMessages.SecurityQuote(decoding: wireData.data)

        let symbol = SymbolID(market: .sh, code: "603986")
        let quote = try #require(LongbridgeProvider.quote(from: wire, symbol: symbol))
        #expect(quote.price == 562.00)
        #expect(quote.previousClose == 611.00)
        #expect(quote.currencyCode == "CNY")
        #expect(quote.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
    }
}
