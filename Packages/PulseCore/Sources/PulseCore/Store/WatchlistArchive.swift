import Foundation

/// A portable, hand-writable snapshot of watchlists and their positions.
///
/// The on-disk `pulse.watchlists.v2` blob is an implementation detail: it stores
/// UUIDs, provider watermarks, and a derived legacy lot cache that only make sense
/// inside one installation. This archive is the user-facing shape instead — lists
/// are identified by name, instruments by market and code — so it survives a
/// reinstall, moves between Macs, and can be typed by hand to bulk-add symbols.
///
/// Everything except `market` and `code` is optional. An entry as small as
/// `{"market": "us", "code": "NVDA"}` imports correctly; the display name is then
/// filled in by the first quote refresh, the same path that upgrades watchlists
/// written by older Pulse versions.
public struct WatchlistArchive: Codable, Sendable, Equatable {
    public static let formatIdentifier = "pulse.watchlist"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var exportedAt: Date?
    public var app: String?
    public var lists: [List]

    public struct List: Codable, Sendable, Equatable {
        public var name: String
        public var entries: [Entry]

        public init(name: String, entries: [Entry]) {
            self.name = name
            self.entries = entries
        }
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var market: Market
        public var code: String
        public var name: String?
        public var type: InstrumentType?
        public var pinned: Bool?
        public var transactions: [PositionTransaction]?

        public init(
            market: Market,
            code: String,
            name: String? = nil,
            type: InstrumentType? = nil,
            pinned: Bool? = nil,
            transactions: [PositionTransaction]? = nil
        ) {
            self.market = market
            self.code = code
            self.name = name
            self.type = type
            self.pinned = pinned
            self.transactions = transactions
        }

        /// Rebuilds the canonical identity. `SymbolID` owns crypto-pair parsing,
        /// index resolution, and per-market code normalization, so a hand-typed
        /// `700`, `BTC/USDT`, or `SPX` all land on the same value the app would
        /// have produced through search.
        public var symbolID: SymbolID {
            SymbolID(market: market, code: code)
        }
    }

    public init(
        exportedAt: Date? = nil,
        app: String? = nil,
        lists: [List]
    ) {
        format = Self.formatIdentifier
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.app = app
        self.lists = lists
    }

    // MARK: - Serialization

    public enum DecodingFailure: Error, Equatable {
        case notJSON
        case wrongFormat(String)
        case unsupportedVersion(Int)
        case noLists
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // The archive is meant to be read and edited by a person, so dates stay
        // ISO-8601 rather than the reference-date doubles UserDefaults storage uses.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func encoded() throws -> String {
        let data = try Self.encoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    /// Parses an archive, rejecting anything that is merely valid JSON. Import is
    /// additive and hard to notice when it silently does nothing, so every reason
    /// a payload cannot be applied is reported rather than swallowed.
    public static func decoded(from text: String) throws -> WatchlistArchive {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw DecodingFailure.notJSON
        }
        let archive: WatchlistArchive
        do {
            archive = try decoder().decode(WatchlistArchive.self, from: data)
        } catch let failure as DecodingFailure {
            throw failure
        } catch {
            throw DecodingFailure.notJSON
        }
        guard archive.format == formatIdentifier else {
            throw DecodingFailure.wrongFormat(archive.format)
        }
        guard archive.version <= currentVersion else {
            throw DecodingFailure.unsupportedVersion(archive.version)
        }
        guard !archive.lists.isEmpty else { throw DecodingFailure.noLists }
        return archive
    }

    // MARK: - Import result

    /// What an import actually changed. Import never deletes, so a report of all
    /// zeros means the archive was already fully represented — a normal outcome
    /// worth telling the user about rather than a failure.
    public struct MergeReport: Sendable, Equatable {
        public var listsCreated: Int = 0
        public var symbolsAdded: Int = 0
        public var symbolsAlreadyPresent: Int = 0
        public var positionsRestored: Int = 0

        public var changedAnything: Bool {
            listsCreated > 0 || symbolsAdded > 0 || positionsRestored > 0
        }

        public init() {}
    }
}
