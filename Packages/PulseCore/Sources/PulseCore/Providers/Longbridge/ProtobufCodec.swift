import Foundation

/// Minimal protobuf (proto3) wire-format codec covering exactly what the Longbridge quote
/// protocol needs: varint (wire type 0) and length-delimited (wire type 2) fields.
/// Hand-rolled to keep PulseCore dependency-free; the message set is small and stable.
enum ProtobufWireType: UInt8 {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

struct ProtobufWriter {
    private(set) var data = Data()

    mutating func appendVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        data.append(UInt8(v))
    }

    private mutating func appendTag(field: Int, type: ProtobufWireType) {
        appendVarint(UInt64(field) << 3 | UInt64(type.rawValue))
    }

    /// proto3 omits zero-valued scalar fields
    mutating func field(_ number: Int, varint value: UInt64) {
        guard value != 0 else { return }
        appendTag(field: number, type: .varint)
        appendVarint(value)
    }

    mutating func field(_ number: Int, int value: Int64) {
        field(number, varint: UInt64(bitPattern: value))
    }

    mutating func field(_ number: Int, string value: String) {
        guard !value.isEmpty else { return }
        field(number, bytes: Data(value.utf8))
    }

    mutating func field(_ number: Int, bytes value: Data) {
        appendTag(field: number, type: .lengthDelimited)
        appendVarint(UInt64(value.count))
        data.append(value)
    }

    mutating func field(_ number: Int, message: ProtobufWriter) {
        field(number, bytes: message.data)
    }
}

enum ProtobufDecodingError: Error {
    case truncated
    case malformedVarint
    case unsupportedWireType(UInt8)
}

/// Streaming field reader. Iterate with `nextField()` and switch on the field number;
/// unknown fields are skipped by the caller via the returned value, matching proto3 semantics.
struct ProtobufReader {
    enum Value {
        case varint(UInt64)
        case bytes(Data)

        var uint: UInt64? {
            if case .varint(let v) = self { return v }
            return nil
        }

        var int: Int64? { uint.map { Int64(bitPattern: $0) } }

        var data: Data? {
            if case .bytes(let d) = self { return d }
            return nil
        }

        var string: String? { data.flatMap { String(data: $0, encoding: .utf8) } }
    }

    private let data: Data
    private var index: Data.Index

    init(_ data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    var isAtEnd: Bool { index == data.endIndex }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < data.endIndex else { throw ProtobufDecodingError.truncated }
            guard shift < 64 else { throw ProtobufDecodingError.malformedVarint }
            let byte = data[index]
            data.formIndex(after: &index)
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
    }

    private mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, data.distance(from: index, to: data.endIndex) >= count else {
            throw ProtobufDecodingError.truncated
        }
        let end = data.index(index, offsetBy: count)
        defer { index = end }
        return data.subdata(in: index..<end)
    }

    mutating func nextField() throws -> (number: Int, value: Value)? {
        guard !isAtEnd else { return nil }
        let tag = try readVarint()
        let number = Int(tag >> 3)
        let rawType = UInt8(tag & 0x7)
        switch ProtobufWireType(rawValue: rawType) {
        case .varint:
            return (number, .varint(try readVarint()))
        case .lengthDelimited:
            let length = Int(try readVarint())
            return (number, .bytes(try readBytes(length)))
        case .fixed64:
            _ = try readBytes(8)
            return try nextField()
        case .fixed32:
            _ = try readBytes(4)
            return try nextField()
        case nil:
            throw ProtobufDecodingError.unsupportedWireType(rawType)
        }
    }
}
