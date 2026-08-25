import Foundation
import MCP
import Observation
import PulseCore

/// Owns the MCP endpoint end to end: the loopback listener, the bearer token,
/// and one `(Server, StatefulHTTPServerTransport)` pair per MCP session. The
/// SDK transport is single-session by design, so the host keys a table off the
/// `Mcp-Session-Id` header it assigns on initialize.
@MainActor
@Observable
final class MCPAgentServer {
    enum Status: Equatable {
        case stopped
        case running(port: UInt16)
        case failed(String)
    }

    /// Debug uses a distinct port so Dev and Release can run side by side.
    static let port: UInt16 = {
        #if DEBUG
        41928
        #else
        41927
        #endif
    }()

    private(set) var status: Status = .stopped

    var endpoint: String { "http://127.0.0.1:\(Self.port)/mcp" }

    private static let sessionCap = 8
    private static let idleTimeout: TimeInterval = 15 * 60

    private struct Session {
        let server: Server
        let transport: StatefulHTTPServerTransport
        var lastActivity: Date
    }

    @ObservationIgnored private let commands: AgentWatchlistCommands
    @ObservationIgnored private let poke: @MainActor () -> Void
    @ObservationIgnored private var listener: MCPHTTPListener?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var sessions: [String: Session] = [:]

    init(commands: AgentWatchlistCommands, poke: @escaping @MainActor () -> Void) {
        self.commands = commands
        self.poke = poke
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil, startTask == nil else { return }
        startTask = Task { await performStart() }
    }

    private func performStart() async {
        defer { startTask = nil }
        do {
            let token = try MCPTokenStore.loadOrCreate()
            let listener = MCPHTTPListener(port: Self.port, token: token) { [weak self] request in
                guard let self else {
                    return .error(statusCode: 503, MCPError.connectionClosed)
                }
                return await self.route(request)
            }
            try await listener.start()
            if Task.isCancelled {
                await listener.stop()
                return
            }
            self.listener = listener
            status = .running(port: Self.port)
        } catch {
            status = .failed(String(describing: error))
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        let listener = self.listener
        let stale = sessions
        self.listener = nil
        sessions = [:]
        status = .stopped
        Task {
            await listener?.stop()
            for session in stale.values {
                await session.server.stop()
                await session.transport.disconnect()
            }
        }
    }

    // MARK: - Token

    func currentToken() throws -> String {
        try MCPTokenStore.loadOrCreate()
    }

    /// The rotated token is in the Keychain before any restart, so a crash
    /// between rotate and restart still leaves the shown token authoritative.
    func rotateToken() throws -> String {
        let token = try MCPTokenStore.rotate()
        let wasRunning = listener != nil || startTask != nil
        if wasRunning {
            stop()
            start()
        }
        return token
    }

    // MARK: - Request routing

    func route(_ request: HTTPRequest) async -> HTTPResponse {
        evictIdleSessions()

        if let sessionID = request.header(HTTPHeaderName.sessionID) {
            guard var session = sessions[sessionID] else {
                return .error(statusCode: 404, MCPError.invalidRequest("Not Found: Unknown or expired session"))
            }
            session.lastActivity = .now
            sessions[sessionID] = session
            let response = await session.transport.handleRequest(request)
            if request.method.uppercased() == "DELETE", response.statusCode == 200 {
                terminate(sessionID)
            }
            return response
        }

        guard request.method.uppercased() == "POST", Self.isInitialize(request.body) else {
            return .error(statusCode: 400, MCPError.invalidRequest("Bad Request: Missing Mcp-Session-Id"))
        }
        return await createSession(for: request)
    }

    private func createSession(for request: HTTPRequest) async -> HTTPResponse {
        while sessions.count >= Self.sessionCap {
            guard let oldest = sessions.min(by: { $0.value.lastActivity < $1.value.lastActivity }) else { break }
            terminate(oldest.key)
        }

        let transport = StatefulHTTPServerTransport()
        let server = Server(
            name: "Pulse",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await MCPToolAdapter(commands: commands, poke: poke).register(on: server)
        do {
            try await server.start(transport: transport)
        } catch {
            return .error(statusCode: 500, MCPError.internalError("Internal error"))
        }

        let response = await transport.handleRequest(request)
        if let sessionID = response.headers[HTTPHeaderName.sessionID] {
            sessions[sessionID] = Session(server: server, transport: transport, lastActivity: .now)
        } else {
            Task { await server.stop() }
        }
        return response
    }

    private static func isInitialize(_ body: Data?) -> Bool {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        return json["method"] as? String == "initialize"
    }

    private func evictIdleSessions() {
        let cutoff = Date.now.addingTimeInterval(-Self.idleTimeout)
        for (id, session) in sessions where session.lastActivity < cutoff {
            terminate(id)
        }
    }

    private func terminate(_ sessionID: String) {
        guard let session = sessions.removeValue(forKey: sessionID) else { return }
        Task {
            await session.server.stop()
            await session.transport.disconnect()
        }
    }
}
