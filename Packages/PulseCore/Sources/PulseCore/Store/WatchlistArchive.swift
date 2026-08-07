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
        /// Kept as written rather than as a `Market`. A typo in one entry should
        /// cost the user that row, not the whole import, so the market is resolved
        /// per entry and reported instead of failing the decode.
        public var market: String
        public var code: String
        public var name: String?
        public var type: InstrumentType?
        public var pinned: Bool?
        public var transactions: [PositionTransaction]?

        public init(
            market: String,
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

        public init(
            market: Market,
            code: String,
            name: String? = nil,
            type: InstrumentType? = nil,
            pinned: Bool? = nil,
            transactions: [PositionTransaction]? = nil
        ) {
            self.init(
                market: market.rawValue,
                code: code,
                name: name,
                type: type,
                pinned: pinned,
                transactions: transactions
            )
        }

        /// What Pulse makes of this entry. Reading it is how the import preview can
        /// show the user the instrument they are actually about to add, rather than
        /// echoing back the text they pasted.
        public enum Resolution: Sendable, Equatable {
            case resolved(SymbolID)
            case unknownMarket
            case missingCode
        }

        public var resolution: Resolution {
            let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawMarket = market.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let market = Market(rawValue: rawMarket) else { return .unknownMarket }
            guard !trimmedCode.isEmpty else { return .missingCode }
            // `SymbolID` owns crypto-pair parsing, index resolution, and per-market
            // code normalization, so a hand-typed `700`, `btc/usdt`, or `SPX` all
            // land on the value search would have produced.
            return .resolved(SymbolID(market: market, code: trimmedCode))
        }

        public var symbolID: SymbolID? {
            guard case .resolved(let symbol) = resolution else { return nil }
            return symbol
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

    /// A minimal, valid archive to hand someone who is writing one by hand. Offering
    /// this to the clipboard teaches the format far better than describing it does.
    public static func example() -> WatchlistArchive {
        WatchlistArchive(lists: [
            .init(name: PulseLocalization.localizedString("data.example.list.stocks"), entries: [
                .init(market: .us, code: "NVDA"),
                .init(market: .hk, code: "700"),
                .init(market: .sh, code: "688018")
            ]),
            .init(name: PulseLocalization.localizedString("data.example.list.crypto"), entries: [
                .init(market: .crypto, code: "BTC/USDT")
            ])
        ])
    }

    // MARK: - Import plan

    /// What an import would do, entry by entry, before anything is written.
    ///
    /// A code that cannot be verified against a provider offline still resolves to
    /// *something*, so the plan shows the instrument Pulse understood rather than a
    /// bare success flag: a wrong market or a mistyped pair is obvious when the
    /// interpretation is on screen next to the text that produced it.
    public struct ImportPlan: Sendable, Equatable {
        public enum Outcome: Sendable, Equatable {
            case add(SymbolID)
            case alreadyInList(SymbolID)
            case restorePosition(SymbolID)
            case skipped(Entry.Resolution)
        }

        public struct Item: Sendable, Equatable, Identifiable {
            public let id: Int
            public let entry: Entry
            public let outcome: Outcome

            public var symbol: SymbolID? {
                switch outcome {
                case .add(let symbol), .alreadyInList(let symbol), .restorePosition(let symbol):
                    symbol
                case .skipped:
                    nil
                }
            }
        }

        public struct ListPlan: Sendable, Equatable, Identifiable {
            public let id: Int
            public let name: String
            public let isNew: Bool
            public let items: [Item]
        }

        public var lists: [ListPlan]

        public var allItems: [Item] { lists.flatMap(\.items) }
        public var newListCount: Int { lists.filter(\.isNew).count }
        public var addCount: Int { allItems.filter { if case .add = $0.outcome { true } else { false } }.count }
        public var skippedCount: Int {
            allItems.filter { if case .skipped = $0.outcome { true } else { false } }.count
        }
        public var restoreCount: Int {
            allItems.filter { if case .restorePosition = $0.outcome { true } else { false } }.count
        }
        public var changesAnything: Bool { newListCount > 0 || addCount > 0 || restoreCount > 0 }
    }
}
