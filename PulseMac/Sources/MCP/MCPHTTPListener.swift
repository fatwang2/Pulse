import Foundation
import MCP
import Network
import OSLog
import Synchronization

/// Minimal HTTP/1.1 + SSE loopback adapter for the MCP endpoint. The MCP SDK's
/// HTTP transport is a request adapter, not a listener, so PulseMac owns the
/// socket: bind to 127.0.0.1 only, enforce bearer auth and Origin before any
/// request reaches the transport, and serve one request per connection.
actor MCPHTTPListener {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    struct ListenerFailure: Error, CustomStringConvertible {
        let description: String
    }

    private static let maxHeaderBytes = 16 * 1024
    private static let maxBodyBytes = 4 * 1024 * 1024
    /// A client that connects but never finishes its request would otherwise
    /// hold the socket (and its fd) forever.
    private static let requestReadTimeout: Duration = .seconds(30)

    private nonisolated let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pulse.mac",
        category: "MCPHTTP"
    )
    private var nextConnectionID: UInt64 = 0

    private let port: UInt16
    private let token: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "app.pulse.mcp.listener")
    private var listener: NWListener?

    init(port: UInt16, token: String, handler: @escaping Handler) {
        self.port = port
        self.token = token
        self.handler = handler
    }

    func start() async throws {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw ListenerFailure(description: "Invalid port \(port)")
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: endpointPort)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            Task { await self.serve(connection) }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // The state handler keeps firing after ready (e.g. on cancel); the
            // continuation must resume exactly once.
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                let outcome: Result<Void, Error>? = switch state {
                case .ready: .success(())
                case .failed(let error): .failure(error)
                case .cancelled: .failure(ListenerFailure(description: "Listener cancelled during start"))
                case .setup, .waiting: nil
                @unknown default: nil
                }
                guard let outcome else { return }
                let shouldResume = resumed.withLock { alreadyResumed in
                    if alreadyResumed { return false }
                    alreadyResumed = true
                    return true
                }
                if shouldResume { continuation.resume(with: outcome) }
            }
            listener.start(queue: queue)
        }
        listener.stateUpdateHandler = nil
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    /// Every path out of here — normal completion, error, timeout, peer
    /// disconnect, task cancellation — must release the socket, or the fd
    /// leaks for the life of the process. The SSE case is the dangerous one:
    /// the transport's stream only ends when the session does, so a client
    /// that drops its GET stream would otherwise leave this task (and the
    /// connection it retains) suspended forever.
    private func serve(_ connection: NWConnection) async {
        nextConnectionID += 1
        let id = nextConnectionID
        let startedAt = ContinuousClock.now
        var outcome = "completed"
        var requestLine = "-"
        logger.debug("Connection #\(id, privacy: .public) accepted")
        defer {
            connection.stateUpdateHandler = nil
            connection.cancel()
            let elapsed = ContinuousClock.now - startedAt
            logger.info("""
                Connection #\(id, privacy: .public) closed after \(elapsed, privacy: .public): \
                \(outcome, privacy: .public) [\(requestLine, privacy: .public)]
                """)
        }

        // A failed connection keeps its resources until cancelled, and
        // cancelling is also what makes any pending send/receive complete
        // (with an error) so a suspended continuation can resume.
        connection.stateUpdateHandler = { [weak connection, logger] state in
            switch state {
            case .failed(let error):
                logger.debug("Connection #\(id, privacy: .public) failed: \(error, privacy: .public)")
                connection?.cancel()
            case .setup, .preparing, .waiting, .ready, .cancelled:
                break
            @unknown default:
                break
            }
        }
        connection.start(queue: queue)

        do {
            let request = try await Self.racing {
                try await self.readRequest(connection)
            } against: {
                try await Task.sleep(for: Self.requestReadTimeout)
                throw ListenerFailure(description: "Timed out waiting for the request")
            }
            requestLine = "\(request.method) \(request.path)"
            let response = await gate(request)
            switch response {
            case .stream(let stream, let headers):
                try await Self.racing {
                    try await self.writeStream(stream, headers: headers, over: connection)
                } against: {
                    try await self.watchPeer(connection)
                }
            default:
                try await write(response, to: connection)
            }
        } catch {
            // Half-open sockets, malformed requests, and peers that went away
            // all just drop the connection; the reason goes to the log.
            outcome = String(describing: error)
        }
    }

    private struct PeerClosed: Error, CustomStringConvertible {
        var description: String { "Peer closed the connection" }
    }

    /// Runs `body` and `watcher` concurrently; the first to finish decides
    /// the outcome and the other is cancelled. `watcher` never returns
    /// normally: it either throws (its condition fired) or is cancelled.
    private nonisolated static func racing<Value: Sendable>(
        _ body: @escaping @Sendable () async throws -> Value,
        against watcher: @escaping @Sendable () async throws -> Void
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value?.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await watcher()
                return nil
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() ?? nil else {
                throw ListenerFailure(description: "Watcher finished without a result")
            }
            return value
        }
    }

    /// One request per connection means the client has nothing more to send
    /// once its request is in, so on an SSE stream a completed receive is the
    /// peer going away: FIN (`isComplete`), RST/ECONNRESET, or a cancelled
    /// connection. Stray bytes are ignored and the watch continues.
    private nonisolated func watchPeer(_ connection: NWConnection) async throws {
        while true {
            guard try await receiveChunk(connection) != nil else {
                throw PeerClosed()
            }
        }
    }

    /// Path, Origin, and bearer checks run here so an unauthenticated request
    /// never reaches the MCP transport.
    private func gate(_ raw: ParsedRequest) async -> HTTPResponse {
        guard raw.path == "/mcp" else {
            return .error(statusCode: 404, MCPError.invalidRequest("Not Found"))
        }
        if let origin = raw.headers.first(where: { $0.key.lowercased() == "origin" })?.value,
           !Self.isLocalOrigin(origin) {
            return .error(statusCode: 403, MCPError.invalidRequest("Forbidden: non-local Origin"))
        }
        let authorization = raw.headers.first { $0.key.lowercased() == "authorization" }?.value
        guard let authorization,
              Self.constantTimeEquals(authorization, "Bearer \(token)") else {
            return .error(
                statusCode: 401,
                MCPError.invalidRequest("Unauthorized"),
                extraHeaders: [HTTPHeaderName.wwwAuthenticate: "Bearer"]
            )
        }
        return await handler(HTTPRequest(
            method: raw.method,
            headers: raw.headers,
            body: raw.body.isEmpty ? nil : raw.body,
            path: raw.path
        ))
    }

    private static func isLocalOrigin(_ origin: String) -> Bool {
        guard let host = URL(string: origin)?.host() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else { return false }
        var difference: UInt8 = 0
        for index in lhsBytes.indices {
            difference |= lhsBytes[index] ^ rhsBytes[index]
        }
        return difference == 0
    }

    // MARK: - HTTP parsing

    private struct ParsedRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func readRequest(_ connection: NWConnection) async throws -> ParsedRequest {
        var buffer = Data()
        let separator = Data("\r\n\r\n".utf8)
        var headerEnd: Range<Data.Index>?
        while headerEnd == nil {
            guard buffer.count < Self.maxHeaderBytes else {
                throw ListenerFailure(description: "Header section too large")
            }
            guard let chunk = try await receiveChunk(connection) else {
                throw ListenerFailure(description: "Connection closed before headers completed")
            }
            buffer.append(chunk)
            headerEnd = buffer.range(of: separator)
        }
        guard let headerEnd else {
            throw ListenerFailure(description: "Missing header terminator")
        }

        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw ListenerFailure(description: "Non-UTF8 header section")
        }
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            throw ListenerFailure(description: "Empty request")
        }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 3 else {
            throw ListenerFailure(description: "Malformed request line")
        }
        let method = String(requestLine[0])
        let target = String(requestLine[1])
        let path = String(target.prefix(while: { $0 != "?" }))

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = headers
            .first { $0.key.lowercased() == "content-length" }
            .flatMap { Int($0.value) } ?? 0
        guard contentLength >= 0, contentLength <= Self.maxBodyBytes else {
            throw ListenerFailure(description: "Body too large")
        }

        var body = Data(buffer[headerEnd.upperBound...])
        while body.count < contentLength {
            guard let chunk = try await receiveChunk(connection) else {
                throw ListenerFailure(description: "Connection closed before body completed")
            }
            body.append(chunk)
        }

        return ParsedRequest(
            method: method,
            path: path,
            headers: headers,
            body: body.prefix(contentLength)
        )
    }

    private nonisolated func receiveChunk(_ connection: NWConnection) async throws -> Data? {
        try await Self.awaitingConnection(connection) { resume in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    resume(.failure(error))
                } else if let data, !data.isEmpty {
                    resume(.success(data))
                } else if isComplete {
                    resume(.success(nil))
                } else {
                    resume(.success(Data()))
                }
            }
        }
    }

    /// Bridges one Network.framework completion into async/await so that the
    /// continuation resumes exactly once, and so that cancelling the awaiting
    /// task cannot strand it: the cancellation handler both resumes with
    /// `CancellationError` and cancels the connection, which makes Network
    /// complete the pending operation (with an error) as well. Whichever
    /// arrives first wins; the other is ignored.
    private nonisolated static func awaitingConnection<Value: Sendable>(
        _ connection: NWConnection,
        _ start: (@escaping @Sendable (Result<Value, any Error>) -> Void) -> Void
    ) async throws -> Value {
        let slot = OneShotContinuation<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                slot.arm(continuation)
                if Task.isCancelled {
                    slot.resume(with: .failure(CancellationError()))
                    return
                }
                start { result in slot.resume(with: result) }
            }
        } onCancel: {
            slot.resume(with: .failure(CancellationError()))
            connection.cancel()
        }
    }

    private final class OneShotContinuation<Value: Sendable>: Sendable {
        private let pending = Mutex<CheckedContinuation<Value, any Error>?>(nil)

        func arm(_ continuation: CheckedContinuation<Value, any Error>) {
            pending.withLock { $0 = continuation }
        }

        func resume(with result: Result<Value, any Error>) {
            let continuation = pending.withLock { slot in
                defer { slot = nil }
                return slot
            }
            continuation?.resume(with: result)
        }
    }

    // MARK: - HTTP writing

    private nonisolated func write(_ response: HTTPResponse, to connection: NWConnection) async throws {
        switch response {
        case .stream(let stream, let headers):
            try await writeStream(stream, headers: headers, over: connection)
        default:
            let body = response.bodyData ?? Data()
            var head = Self.head(status: response.statusCode, headers: response.headers, streaming: false, bodyCount: body.count)
            head.append(body)
            try await send(head, over: connection)
        }
    }

    /// Chunked SSE. The transport's stream ends only when it closes the
    /// stream itself (final response, session end); peer disconnects are
    /// detected by `watchPeer`, which cancels this task. Iterating an
    /// `AsyncThrowingStream` honours cancellation by ending the loop.
    private nonisolated func writeStream(
        _ stream: AsyncThrowingStream<Data, any Error>,
        headers: [String: String],
        over connection: NWConnection
    ) async throws {
        try await send(Self.head(status: 200, headers: headers, streaming: true), over: connection)
        do {
            for try await chunk in stream {
                try await send(Self.chunkFrame(chunk), over: connection)
            }
        } catch {
            // The transport ended the stream abnormally; terminate below either way.
        }
        try Task.checkCancellation()
        try await send(Data("0\r\n\r\n".utf8), over: connection)
    }

    private static func head(status: Int, headers: [String: String], streaming: Bool, bodyCount: Int = 0) -> Data {
        var text = "HTTP/1.1 \(status) \(reason(for: status))\r\n"
        for (name, value) in headers where !managedHeaderNames.contains(name.lowercased()) {
            text += "\(name): \(value)\r\n"
        }
        if streaming {
            text += "Transfer-Encoding: chunked\r\n"
        } else {
            text += "Content-Length: \(bodyCount)\r\n"
        }
        text += "Connection: close\r\n\r\n"
        return Data(text.utf8)
    }

    /// Framing is decided here (one response per connection, chunked SSE), so
    /// framing-related headers suggested by the transport are dropped.
    private static let managedHeaderNames: Set<String> = ["content-length", "transfer-encoding", "connection"]

    private static func chunkFrame(_ chunk: Data) -> Data {
        var frame = Data(String(format: "%x\r\n", chunk.count).utf8)
        frame.append(chunk)
        frame.append(Data("\r\n".utf8))
        return frame
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: ""
        }
    }

    private nonisolated func send(_ data: Data, over connection: NWConnection) async throws {
        try await Self.awaitingConnection(connection) { (resume: @escaping @Sendable (Result<Void, any Error>) -> Void) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    resume(.failure(error))
                } else {
                    resume(.success(()))
                }
            })
        }
    }
}
