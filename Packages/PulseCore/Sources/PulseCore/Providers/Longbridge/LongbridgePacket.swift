import Foundation
import Compression

/// Longbridge OpenAPI socket packet framing (BigEndian, "Longbridge Protocol" v1).
/// Reference: https://open.longbridge.com/docs/socket/protocol/overview
///
/// Request  (type 1): [flags|type][cmd][request_id u32][timeout u16][body_len u24][body]
/// Response (type 2): [flags|type][cmd][request_id u32][status u8][body_len u24][body]
/// Push     (type 3): [flags|type][cmd][body_len u24][body]
/// The first byte packs the packet type in its LOW nibble, verify in bit 4 and gzip in bit 5 —
/// the docs' bit diagram reads MSB-first, but the reference implementation packs LSB-first
/// (openapi-protocol/go/v1/header.go: `(type & 0xf) | (verify << 4) | (gzip << 5)`).
enum LongbridgePacket {
    enum Kind: UInt8 {
        case request = 1
        case response = 2
        case push = 3
    }

    struct Response {
        var command: UInt8
        var requestID: UInt32
        var status: UInt8
        var body: Data
    }

    struct Push {
        var command: UInt8
        var body: Data
    }

    enum Inbound {
        case response(Response)
        case push(Push)
        /// Heartbeat *requests* initiated by the server; the client must echo the body back.
        case serverRequest(command: UInt8, requestID: UInt32, body: Data)
    }

    enum FramingError: Error {
        case truncated
        case unknownPacketType(UInt8)
        case verifiedPacketUnsupported
        case malformedGzipBody
    }

    // MARK: - Encoding

    static func encodeRequest(command: UInt8, requestID: UInt32, body: Data, timeoutMS: UInt16 = 10_000) -> Data {
        var data = Data(capacity: 11 + body.count)
        data.append(Kind.request.rawValue)
        data.append(command)
        data.appendBigEndian(requestID)
        data.appendBigEndian(timeoutMS)
        data.appendUInt24(UInt32(body.count))
        data.append(body)
        return data
    }

    static func encodeResponse(command: UInt8, requestID: UInt32, status: UInt8, body: Data) -> Data {
        var data = Data(capacity: 10 + body.count)
        data.append(Kind.response.rawValue)
        data.append(command)
        data.appendBigEndian(requestID)
        data.append(status)
        data.appendUInt24(UInt32(body.count))
        data.append(body)
        return data
    }

    // MARK: - Decoding

    /// Parses every packet contained in one WebSocket binary message.
    static func decode(_ data: Data) throws -> [Inbound] {
        var packets: [Inbound] = []
        var cursor = LongbridgeByteCursor(data)
        while !cursor.isAtEnd {
            let head = try cursor.byte()
            let kind = head & 0x0F
            let verified = head >> 4 & 0x1 != 0
            let gzipped = head >> 5 & 0x1 != 0
            guard !verified else { throw FramingError.verifiedPacketUnsupported }

            switch Kind(rawValue: kind) {
            case .request:
                let command = try cursor.byte()
                let requestID = try cursor.uint32()
                _ = try cursor.uint16() // timeout: irrelevant for server-initiated requests
                let body = try body(&cursor, gzipped: gzipped)
                packets.append(.serverRequest(command: command, requestID: requestID, body: body))
            case .response:
                let command = try cursor.byte()
                let requestID = try cursor.uint32()
                let status = try cursor.byte()
                let body = try body(&cursor, gzipped: gzipped)
                packets.append(.response(Response(command: command, requestID: requestID, status: status, body: body)))
            case .push:
                let command = try cursor.byte()
                let body = try body(&cursor, gzipped: gzipped)
                packets.append(.push(Push(command: command, body: body)))
            case nil:
                throw FramingError.unknownPacketType(kind)
            }
        }
        return packets
    }

    private static func body(_ cursor: inout LongbridgeByteCursor, gzipped: Bool) throws -> Data {
        let length = try cursor.uint24()
        let raw = try cursor.bytes(Int(length))
        return gzipped ? try gunzip(raw) : raw
    }

    // MARK: - Gzip

    /// Bodies arrive gzip-wrapped when the gzip flag is set: RFC 1952 header + raw deflate + CRC32/ISIZE trailer.
    static func gunzip(_ data: Data) throws -> Data {
        guard data.count > 18, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B,
              data[data.startIndex + 2] == 8 else {
            throw FramingError.malformedGzipBody
        }
        let flags = data[data.startIndex + 3]
        var offset = data.startIndex + 10
        func advance(_ n: Int) throws {
            guard data.distance(from: offset, to: data.endIndex) >= n else { throw FramingError.malformedGzipBody }
            offset = data.index(offset, offsetBy: n)
        }
        if flags & 0x04 != 0 { // FEXTRA
            try advance(2)
            let xlen = Int(data[data.index(offset, offsetBy: -2)]) | Int(data[data.index(offset, offsetBy: -1)]) << 8
            try advance(xlen)
        }
        for flag in [UInt8(0x08), 0x10] where flags & flag != 0 { // FNAME / FCOMMENT: null-terminated
            while offset < data.endIndex, data[offset] != 0 { offset = data.index(after: offset) }
            try advance(1)
        }
        if flags & 0x02 != 0 { try advance(2) } // FHCRC

        guard data.distance(from: offset, to: data.endIndex) > 8 else { throw FramingError.malformedGzipBody }
        let deflated = data.subdata(in: offset..<data.index(data.endIndex, offsetBy: -8))
        // ISIZE trailer: uncompressed size mod 2^32, little-endian
        let sizeBytes = data.suffix(4)
        let expectedSize = sizeBytes.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        guard expectedSize > 0, expectedSize <= 16 * 1024 * 1024 else { throw FramingError.malformedGzipBody }

        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { destination.deallocate() }
        let written = deflated.withUnsafeBytes { source in
            compression_decode_buffer(
                destination, expectedSize,
                source.bindMemory(to: UInt8.self).baseAddress!, deflated.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written == expectedSize else { throw FramingError.malformedGzipBody }
        return Data(bytes: destination, count: written)
    }
}

/// Sequential BigEndian byte reader over a Data buffer.
struct LongbridgeByteCursor {
    private let data: Data
    private var index: Data.Index

    init(_ data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    var isAtEnd: Bool { index == data.endIndex }

    mutating func byte() throws -> UInt8 {
        guard index < data.endIndex else { throw LongbridgePacket.FramingError.truncated }
        defer { data.formIndex(after: &index) }
        return data[index]
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, data.distance(from: index, to: data.endIndex) >= count else {
            throw LongbridgePacket.FramingError.truncated
        }
        let end = data.index(index, offsetBy: count)
        defer { index = end }
        return data.subdata(in: index..<end)
    }

    mutating func uint16() throws -> UInt16 {
        try (0..<2).reduce(0) { acc, _ in try acc << 8 | UInt16(byte()) }
    }

    mutating func uint24() throws -> UInt32 {
        try (0..<3).reduce(0) { acc, _ in try acc << 8 | UInt32(byte()) }
    }

    mutating func uint32() throws -> UInt32 {
        try (0..<4).reduce(0) { acc, _ in try acc << 8 | UInt32(byte()) }
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func appendBigEndian(_ value: UInt16) {
        append(contentsOf: [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func appendUInt24(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}
