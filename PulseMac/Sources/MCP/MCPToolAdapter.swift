import Foundation
import MCP
import PulseCore

/// Bridges MCP tool calls onto `AgentWatchlistCommands`. Store policy (required
/// group ids, selection restore, idempotent retries) lives in the facade; this
/// layer only decodes strict JSON arguments and encodes results and errors.
@MainActor
final class MCPToolAdapter {
    private let commands: AgentWatchlistCommands
    private let poke: @MainActor () -> Void

    init(commands: AgentWatchlistCommands, poke: @escaping @MainActor () -> Void) {
        self.commands = commands
        self.poke = poke
    }

    func register(on server: Server) async {
        let tools = Self.specs.map(\.tool)
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { [self] params in
            await call(params)
        }
    }

    func call(_ params: CallTool.Parameters) async -> CallTool.Result {
        guard let spec = Self.specsByName[params.name] else {
            return Self.failureResult(ToolFailure(
                code: "unknown_tool",
                message: "No tool named \(params.name). Call tools/list for the available tools."
            ))
        }
        do {
            let arguments = try ToolArguments(params.arguments, allowed: spec.argumentNames)
            return try await spec.run(self, arguments)
        } catch let failure as ToolFailure {
            return Self.failureResult(failure)
        } catch {
            return Self.failureResult(ToolFailure(code: "internal_error", message: "Internal error"))
        }
    }

    // MARK: - Tool registry

    private struct ToolSpec {
        let tool: Tool
        let argumentNames: Set<String>
        let run: @MainActor (MCPToolAdapter, ToolArguments) async throws -> CallTool.Result

        init(
            name: String,
            description: String,
            properties: [String: Value] = [:],
            required: [String] = [],
            readOnly: Bool = false,
            run: @escaping @MainActor (MCPToolAdapter, ToolArguments) async throws -> CallTool.Result
        ) {
            self.tool = Tool(
                name: name,
                description: description,
                inputSchema: .object([
                    "type": "object",
                    "properties": .object(properties),
                    "required": .array(required.map { .string($0) }),
                    "additionalProperties": .bool(false),
                ]),
                annotations: .init(readOnlyHint: readOnly, openWorldHint: false)
            )
            self.argumentNames = Set(properties.keys)
            self.run = run
        }
    }

    private static let specs: [ToolSpec] = [
        ToolSpec(
            name: "list_watchlists",
            description: "List every watchlist group with its id, name, and symbols.",
            readOnly: true
        ) { adapter, _ in
            try MCPToolAdapter.success(adapter.commands.listWatchlists())
        },
        ToolSpec(
            name: "list_positions",
            description: "List every watchlist symbol that has position history, with holdings, cost, realized P&L, transactions, and the cached quote.",
            readOnly: true
        ) { adapter, _ in
            try MCPToolAdapter.success(adapter.commands.listPositions())
        },
        ToolSpec(
            name: "get_quotes",
            description: "Get cached quotes for the given symbols. Quotes come from the app's in-memory cache; a symbol without a cached quote returns null.",
            properties: ["symbols": .object(["type": "array", "items": symbolSchema])],
            required: ["symbols"],
            readOnly: true
        ) { adapter, arguments in
            let refs = try arguments.symbolArray("symbols")
            let payload = refs.map { ref in
                QuotePayload(symbol: ref, quote: adapter.commands.quotes(for: [ref]).first)
            }
            return try MCPToolAdapter.success(payload)
        },
        ToolSpec(
            name: "search_symbols",
            description: "Search instruments by name or ticker across markets. Call this before add_symbol to resolve the exact market and code.",
            properties: ["query": .object(["type": "string"])],
            required: ["query"],
            readOnly: true
        ) { adapter, arguments in
            let query = try arguments.string("query")
            return try MCPToolAdapter.success(MCPToolAdapter.unwrap(await adapter.commands.searchSymbols(query)))
        },
        ToolSpec(
            name: "create_group",
            description: "Create a new watchlist group. The name must be unique (case-insensitive) and at most 20 characters.",
            properties: ["name": .object(["type": "string"])],
            required: ["name"]
        ) { adapter, arguments in
            let mutation = try MCPToolAdapter.unwrap(adapter.commands.createGroup(named: arguments.string("name")))
            return try adapter.appliedValue(mutation)
        },
        ToolSpec(
            name: "rename_group",
            description: "Rename an existing watchlist group.",
            properties: ["group_id": uuidSchema, "name": .object(["type": "string"])],
            required: ["group_id", "name"]
        ) { adapter, arguments in
            let group = try MCPToolAdapter.unwrap(adapter.commands.renameGroup(
                arguments.uuid("group_id"),
                to: arguments.string("name")
            ))
            return try MCPToolAdapter.success(group)
        },
        ToolSpec(
            name: "delete_group",
            description: "Delete a watchlist group. The last remaining group cannot be deleted.",
            properties: ["group_id": uuidSchema],
            required: ["group_id"]
        ) { adapter, arguments in
            let mutation = try MCPToolAdapter.unwrap(adapter.commands.deleteGroup(arguments.uuid("group_id")))
            return try adapter.appliedVoid(mutation)
        },
        ToolSpec(
            name: "reorder_groups",
            description: "Set the watchlist tag-bar order. Pass every current group_id exactly once, in the desired left-to-right order. Selection and memberships are unchanged.",
            properties: [
                "group_ids": .object([
                    "type": "array",
                    "items": uuidSchema,
                ]),
            ],
            required: ["group_ids"]
        ) { adapter, arguments in
            let mutation = try MCPToolAdapter.unwrap(
                adapter.commands.reorderGroups(arguments.uuidArray("group_ids"))
            )
            return try adapter.appliedValue(mutation)
        },
        ToolSpec(
            name: "reorder_symbols",
            description: "Set Custom Order for a watchlist group. Pass every symbol in the group exactly once. Pin membership is preserved; the stored order is coerced to pinned-first using relative order within each section. Does not switch the UI into change%/market-value automatic sort.",
            properties: [
                "group_id": uuidSchema,
                "symbols": .object(["type": "array", "items": symbolSchema]),
            ],
            required: ["group_id", "symbols"]
        ) { adapter, arguments in
            let mutation = try MCPToolAdapter.unwrap(adapter.commands.reorderSymbols(
                arguments.symbolArray("symbols"),
                in: arguments.uuid("group_id")
            ))
            return try adapter.appliedValue(mutation)
        },
        ToolSpec(
            name: "add_symbol",
            description: "Add a symbol to a watchlist group. group_id is required; use search_symbols first to resolve market/code and pass the resolved name.",
            properties: [
                "symbol": symbolSchema,
                "group_id": uuidSchema,
                "name": .object(["type": "string"]),
                "type": .object([
                    "type": "string",
                    "enum": .array([InstrumentType.equity, .etf, .index, .fund, .crypto, .commodity, .other].map { .string($0.rawValue) }),
                ]),
            ],
            required: ["symbol", "group_id"]
        ) { adapter, arguments in
            let mutation = try MCPToolAdapter.unwrap(adapter.commands.addSymbol(
                arguments.symbol("symbol"),
                name: arguments.optionalString("name"),
                type: arguments.optionalInstrumentType("type"),
                to: arguments.uuid("group_id")
            ))
            return try adapter.appliedValue(mutation)
        },
        ToolSpec(
            name: "remove_symbol",
            description: "Remove a symbol from a watchlist group. Removing a symbol that is not in the group succeeds with alreadyApplied=true.",
            properties: ["symbol": symbolSchema, "group_id": uuidSchema],
            required: ["symbol", "group_id"]
        ) { adapter, arguments in
            let mutation = try MCPToolAdapter.unwrap(adapter.commands.removeSymbol(
                arguments.symbol("symbol"),
                from: arguments.uuid("group_id")
            ))
            return try adapter.appliedVoid(mutation)
        },
        ToolSpec(
            name: "record_trade",
            description: "Record a buy or sell for a symbol already on the watchlist. The date is the trade day in the user's local calendar. Pass a stable id to make retries idempotent.",
            properties: [
                "symbol": symbolSchema,
                "kind": .object(["type": "string", "enum": .array([.string("buy"), .string("sell")])]),
                "quantity": .object(["type": "number"]),
                "price": .object(["type": "number"]),
                "date": tradeDateSchema,
                "id": uuidSchema,
            ],
            required: ["symbol", "kind", "quantity", "price", "date"]
        ) { adapter, arguments in
            let draft = AgentTradeDraft(
                symbol: try arguments.symbol("symbol"),
                kind: try arguments.tradeKind("kind"),
                quantity: try arguments.double("quantity"),
                price: try arguments.double("price"),
                date: try arguments.date("date"),
                id: try arguments.optionalUUID("id")
            )
            let mutation = try MCPToolAdapter.unwrap(adapter.commands.recordTrade(draft))
            return try adapter.appliedValue(mutation)
        },
        ToolSpec(
            name: "delete_trade",
            description: "Delete one recorded transaction by id; position and P&L are recalculated.",
            properties: ["symbol": symbolSchema, "id": uuidSchema],
            required: ["symbol", "id"]
        ) { adapter, arguments in
            let mutation = try MCPToolAdapter.unwrap(adapter.commands.deleteTrade(
                symbol: arguments.symbol("symbol"),
                id: arguments.uuid("id")
            ))
            return try adapter.appliedValue(mutation)
        },
        ToolSpec(
            name: "calibrate_position",
            description: "Overwrite a position to an exact quantity and average cost as one calibration entry. The date is the calibration day in the user's local calendar. Without an id this is not idempotent across retries.",
            properties: [
                "symbol": symbolSchema,
                "quantity": .object(["type": "number"]),
                "average_cost": .object(["type": "number"]),
                "date": tradeDateSchema,
                "id": uuidSchema,
            ],
            required: ["symbol", "quantity", "average_cost", "date"]
        ) { adapter, arguments in
            let mutation = try MCPToolAdapter.unwrap(adapter.commands.calibratePosition(
                symbol: arguments.symbol("symbol"),
                quantity: arguments.double("quantity"),
                averageCost: arguments.double("average_cost"),
                date: arguments.date("date"),
                id: arguments.optionalUUID("id")
            ))
            return try adapter.appliedValue(mutation)
        },
    ]

    private static let specsByName = Dictionary(uniqueKeysWithValues: specs.map { ($0.tool.name, $0) })

    // MARK: - Schemas

    private static let symbolSchema: Value = .object([
        "type": "object",
        "properties": .object([
            "market": .object([
                "type": "string",
                "enum": .array(Market.allCases.map { .string($0.rawValue) }),
            ]),
            "code": .object(["type": "string"]),
        ]),
        "required": .array(["market", "code"]),
        "additionalProperties": .bool(false),
    ])

    private static let uuidSchema: Value = .object(["type": "string", "format": "uuid"])
    private static let tradeDateSchema: Value = .object([
        "type": "string",
        "format": "date",
        "description": "Trade day as YYYY-MM-DD in the user's local calendar. A full ISO 8601 date-time is also accepted and filed under the local day it falls on.",
    ])

    // MARK: - Results

    private struct MutationPayload<Payload: Codable & Sendable>: Codable, Sendable {
        let value: Payload
        let alreadyApplied: Bool
    }

    private struct AppliedPayload: Codable, Sendable {
        let alreadyApplied: Bool
    }

    private struct QuotePayload: Codable, Sendable {
        let symbol: AgentSymbolRef
        let quote: AgentQuoteSnapshot?
    }

    private func appliedValue<Payload: Codable & Sendable>(
        _ mutation: AgentMutation<Payload>
    ) throws -> CallTool.Result {
        if mutation.didChangeSymbolUnion { poke() }
        return try Self.success(MutationPayload(value: mutation.value, alreadyApplied: mutation.alreadyApplied))
    }

    private func appliedVoid(_ mutation: AgentMutation<Void>) throws -> CallTool.Result {
        if mutation.didChangeSymbolUnion { poke() }
        return try Self.success(AppliedPayload(alreadyApplied: mutation.alreadyApplied))
    }

    private static func success<Payload: Codable>(_ payload: Payload) throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
    }

    private static func failureResult(_ failure: ToolFailure) -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = (try? encoder.encode(failure)).map { String(decoding: $0, as: UTF8.self) }
            ?? #"{"code":"internal_error","message":"Internal error"}"#
        return CallTool.Result(
            content: [.text(text: body, annotations: nil, _meta: nil)],
            isError: true
        )
    }

    private static func unwrap<Payload>(_ result: Result<Payload, AgentWatchlistError>) throws -> Payload {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw failure(error)
        }
    }

    private static func failure(_ error: AgentWatchlistError) -> ToolFailure {
        let markets = Market.allCases.map(\.rawValue).joined(separator: ", ")
        return switch error {
        case .groupNotFound(let id):
            ToolFailure(code: "group_not_found", message: "No watchlist group with id \(id.uuidString). Call list_watchlists for valid group ids.")
        case .symbolNotFound(let ref):
            ToolFailure(code: "symbol_not_found", message: "\(ref.market):\(ref.code) is not on the watchlist.")
        case .invalidSymbol(let ref):
            ToolFailure(code: "invalid_symbol", message: "\(ref.market):\(ref.code) is not a valid symbol reference. market must be one of: \(markets).")
        case .invalidName:
            ToolFailure(code: "invalid_name", message: "The name must be non-empty after trimming and at most 20 characters.")
        case .duplicateGroupName(let name):
            ToolFailure(code: "duplicate_group_name", message: "A group named \(name) already exists (names are case-insensitive).")
        case .lastGroupProtected:
            ToolFailure(code: "last_group_protected", message: "The last remaining group cannot be deleted.")
        case .positionNotSupported:
            ToolFailure(code: "position_not_supported", message: "This instrument does not support positions.")
        case .itemNotOnWatchlist:
            ToolFailure(code: "item_not_on_watchlist", message: "The symbol is not on any watchlist. Call add_symbol first.")
        case .invalidQuantity:
            ToolFailure(code: "invalid_quantity", message: "quantity must be a finite number greater than 0.")
        case .invalidPrice:
            ToolFailure(code: "invalid_price", message: "price must be a finite, non-negative number.")
        case .transactionNotFound(let id):
            ToolFailure(code: "transaction_not_found", message: "No transaction with id \(id.uuidString).")
        case .searchUnavailable:
            ToolFailure(code: "search_unavailable", message: "Symbol search is not available.")
        case .searchFailed(let message):
            ToolFailure(code: "search_failed", message: message)
        case .invalidGroupOrder:
            ToolFailure(
                code: "invalid_group_order",
                message: "group_ids must be a permutation of every current watchlist group id. Call list_watchlists first."
            )
        case .invalidSymbolOrder:
            ToolFailure(
                code: "invalid_symbol_order",
                message: "symbols must be a permutation of every member of the target group. Call list_watchlists first."
            )
        }
    }
}

// MARK: - Strict argument decoding

struct ToolFailure: Error, Codable, Sendable {
    let code: String
    let message: String
}

/// Strict wrapper over CallTool arguments: unknown keys, missing keys, and
/// wrong-typed values are all rejected with instructive errors instead of
/// being silently coerced or ignored.
struct ToolArguments {
    private let values: [String: Value]

    init(_ raw: [String: Value]?, allowed: Set<String>) throws {
        let values = raw ?? [:]
        if let unknown = values.keys.first(where: { !allowed.contains($0) }) {
            throw ToolFailure(
                code: "invalid_arguments",
                message: "Unknown argument \(unknown). Allowed arguments: \(allowed.sorted().joined(separator: ", "))."
            )
        }
        self.values = values
    }

    func string(_ key: String) throws -> String {
        guard let value = values[key] else { throw Self.missing(key) }
        guard case .string(let string) = value else { throw Self.wrongType(key, expected: "string") }
        return string
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = values[key] else { return nil }
        guard case .string(let string) = value else { throw Self.wrongType(key, expected: "string") }
        return string
    }

    func double(_ key: String) throws -> Double {
        guard let value = values[key] else { throw Self.missing(key) }
        switch value {
        case .double(let double): return double
        case .int(let int): return Double(int)
        default: throw Self.wrongType(key, expected: "number")
        }
    }

    func uuid(_ key: String) throws -> UUID {
        guard let uuid = UUID(uuidString: try string(key)) else {
            throw Self.wrongType(key, expected: "UUID string")
        }
        return uuid
    }

    func optionalUUID(_ key: String) throws -> UUID? {
        guard let string = try optionalString(key) else { return nil }
        guard let uuid = UUID(uuidString: string) else {
            throw Self.wrongType(key, expected: "UUID string")
        }
        return uuid
    }

    func date(_ key: String) throws -> Date {
        guard let date = AgentTradeDate.parse(try string(key)) else {
            throw Self.wrongType(
                key,
                expected: "a trade day as YYYY-MM-DD (e.g. 2026-08-25) or an ISO 8601 date-time (e.g. 2026-08-25T14:30:00Z)"
            )
        }
        return date
    }

    func tradeKind(_ key: String) throws -> AgentTradeKind {
        guard let kind = AgentTradeKind(rawValue: try string(key)) else {
            throw Self.wrongType(key, expected: "\"buy\" or \"sell\"")
        }
        return kind
    }

    func optionalInstrumentType(_ key: String) throws -> InstrumentType? {
        guard let string = try optionalString(key) else { return nil }
        guard let type = InstrumentType(rawValue: string) else {
            throw Self.wrongType(key, expected: "one of the instrument type values from the schema")
        }
        return type
    }

    func symbol(_ key: String) throws -> AgentSymbolRef {
        guard let value = values[key] else { throw Self.missing(key) }
        return try Self.symbolRef(value, key: key)
    }

    func symbolArray(_ key: String) throws -> [AgentSymbolRef] {
        guard let value = values[key] else { throw Self.missing(key) }
        guard case .array(let items) = value else { throw Self.wrongType(key, expected: "array of {market, code} objects") }
        return try items.map { try Self.symbolRef($0, key: key) }
    }

    func uuidArray(_ key: String) throws -> [UUID] {
        guard let value = values[key] else { throw Self.missing(key) }
        guard case .array(let items) = value else { throw Self.wrongType(key, expected: "array of UUID strings") }
        return try items.map { item in
            guard case .string(let string) = item, let uuid = UUID(uuidString: string) else {
                throw Self.wrongType(key, expected: "array of UUID strings")
            }
            return uuid
        }
    }

    private static func symbolRef(_ value: Value, key: String) throws -> AgentSymbolRef {
        guard case .object(let fields) = value else {
            throw wrongType(key, expected: "{market, code} object")
        }
        if let unknown = fields.keys.first(where: { $0 != "market" && $0 != "code" }) {
            throw ToolFailure(code: "invalid_arguments", message: "Unknown field \(unknown) in \(key); only market and code are allowed.")
        }
        guard case .string(let market)? = fields["market"],
              case .string(let code)? = fields["code"] else {
            throw wrongType(key, expected: "{market, code} object with string fields")
        }
        return AgentSymbolRef(market: market, code: code)
    }

    private static func missing(_ key: String) -> ToolFailure {
        ToolFailure(code: "invalid_arguments", message: "Missing required argument \(key).")
    }

    private static func wrongType(_ key: String, expected: String) -> ToolFailure {
        ToolFailure(code: "invalid_arguments", message: "Argument \(key) must be \(expected).")
    }
}
