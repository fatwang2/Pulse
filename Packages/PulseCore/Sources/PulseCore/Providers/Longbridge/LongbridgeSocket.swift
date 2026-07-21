import Foundation

public enum LongbridgeConnectionIssue: Sendable, Equatable {
    case connectionLimit
    case authentication
    case rateLimited
    case network
    case server
}

public enum LongbridgeConnectionStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case reconnecting
    case connected
    case failed(LongbridgeConnectionIssue)
}

/// Small transport seam so connection lifecycle behavior can be regression-tested without
/// opening real Longbridge sockets.
protocol LongbridgeWebSocket: AnyObject, Sendable {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: LongbridgeWebSocket {}

/// One persistent connection to the Longbridge quote gateway. Connection establishment is
/// single-flight: polling, watchlist streaming, and detail loading can all arrive together,
/// but they await the same authenticated socket instead of minting parallel OTPs/connections.
actor LongbridgeSocket {
    static let endpoint = URL(string: "wss://openapi-quote.longbridge.com/v2?version=1&codec=1&platform=9")!

    typealias OTPSource = @Sendable () async throws -> String
    typealias SocketFactory = @Sendable (URL) -> any LongbridgeWebSocket

    private enum ControlMode {
        case authenticate(otp: String)
        case reconnect(sessionID: String)

        var command: LongbridgeCommand {
            switch self {
            case .authenticate: .auth
            case .reconnect: .reconnect
            }
        }

        var body: Data {
            switch self {
            case .authenticate(let otp):
                LongbridgeMessages.authRequest(
                    otp: otp,
                    metadata: ["need_over_night_quote": "true"]
                )
            case .reconnect(let sessionID):
                LongbridgeMessages.reconnectRequest(
                    sessionID: sessionID,
                    metadata: ["need_over_night_quote": "true"]
                )
            }
        }
    }

    private enum LifecycleError: Error {
        case authenticationRejected(status: UInt8)
        case reconnectRejected(status: UInt8)
        case superseded
    }

    private struct ResumeSession: Sendable {
        var id: String
        var expires: Int64

        var isUsable: Bool {
            !id.isEmpty && (expires == 0 || TimeInterval(expires) > Date.now.timeIntervalSince1970 + 5)
        }
    }

    private var otpSource: OTPSource?
    private var onPush: (@Sendable (UInt8, Data) -> Void)?
    private var onRecovered: (@Sendable () -> Void)?
    private var status: LongbridgeConnectionStatus = .disconnected
    private var statusContinuation: AsyncStream<LongbridgeConnectionStatus>.Continuation?

    private var task: (any LongbridgeWebSocket)?
    private var connectionGeneration: UUID?
    private var authenticated = false
    private var connectionAttempt: Task<Void, any Error>?
    private var connectionAttemptID: UUID?
    private var receiveLoop: Task<Void, Never>?
    private var heartbeatLoop: Task<Void, Never>?
    private var resumeSession: ResumeSession?
    private var lastCloseNotice: LongbridgeMessages.CloseNotice?
    private var hasConnectedBefore = false

    private var nextRequestID: UInt32 = 1
    private var pending: [UInt32: CheckedContinuation<LongbridgePacket.Response, any Error>] = [:]
    private let socketFactory: SocketFactory
    private let requestTimeout: Duration = .seconds(10)

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.socketFactory = { url in session.webSocketTask(with: url) }
    }

    init(socketFactory: @escaping SocketFactory) {
        self.socketFactory = socketFactory
    }

    func updateOTPSource(_ source: OTPSource?) {
        otpSource = source
        connectionAttempt?.cancel()
        connectionAttempt = nil
        connectionAttemptID = nil
        disconnect(reason: "auth changed", clearSession: true)
        setStatus(.disconnected)
    }

    func resetConnection() {
        connectionAttempt?.cancel()
        connectionAttempt = nil
        connectionAttemptID = nil
        disconnect(reason: "manual retry", clearSession: false)
        setStatus(.disconnected)
    }

    func setPushHandler(_ handler: (@Sendable (UInt8, Data) -> Void)?) {
        onPush = handler
    }

    /// The transport can resume a socket session, but callers still need to restore any
    /// business subscriptions that were attached to the replaced WebSocket.
    func setRecoveryHandler(_ handler: (@Sendable () -> Void)?) {
        onRecovered = handler
    }

    func statusUpdates() -> AsyncStream<LongbridgeConnectionStatus> {
        statusContinuation?.finish()
        let pair = AsyncStream<LongbridgeConnectionStatus>.makeStream()
        statusContinuation = pair.continuation
        pair.continuation.yield(status)
        return pair.stream
    }

    // MARK: - Requests

    func request(_ command: LongbridgeCommand, body: Data) async throws -> Data {
        try await ensureConnected()
        guard authenticated, let task, let generation = connectionGeneration else {
            throw LongbridgeError.socket("not authenticated")
        }
        let response = try await send(command: command, body: body, on: task, generation: generation)
        return try Self.unwrap(response)
    }

    private static func unwrap(_ response: LongbridgePacket.Response) throws -> Data {
        switch response.status {
        case 0: return response.body
        case 5: throw ProviderError.badResponse("Longbridge socket unauthenticated")
        case 1: throw ProviderError.badResponse("Longbridge request timed out on server")
        default: throw ProviderError.badResponse("Longbridge socket status \(response.status)")
        }
    }

    private func send(command: LongbridgeCommand, body: Data,
                      on socket: any LongbridgeWebSocket, generation: UUID) async throws -> LongbridgePacket.Response {
        guard connectionGeneration == generation else { throw LifecycleError.superseded }
        let requestID = nextRequestID
        nextRequestID = nextRequestID == .max ? 1 : nextRequestID + 1
        let frame = LongbridgePacket.encodeRequest(command: command.rawValue, requestID: requestID, body: body)

        let timeout = Task { [requestTimeout] in
            try? await Task.sleep(for: requestTimeout)
            self.fail(requestID, with: ProviderError.network(underlying: "Longbridge request timed out"))
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending[requestID] = continuation
            Task {
                do {
                    try await socket.send(.data(frame))
                } catch {
                    self.fail(requestID, with: ProviderError.network(underlying: error.localizedDescription))
                    self.connectionLost(generation: generation)
                }
            }
        }
    }

    private func fail(_ requestID: UInt32, with error: any Error) {
        pending.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    // MARK: - Connection lifecycle

    private func ensureConnected() async throws {
        if authenticated, task != nil { return }
        if let connectionAttempt {
            try await connectionAttempt.value
            return
        }

        let attemptID = UUID()
        let attempt = Task { try await self.establishConnection(attemptID: attemptID) }
        connectionAttemptID = attemptID
        connectionAttempt = attempt

        do {
            try await attempt.value
            if connectionAttemptID == attemptID {
                connectionAttempt = nil
                connectionAttemptID = nil
            }
        } catch {
            if connectionAttemptID == attemptID {
                connectionAttempt = nil
                connectionAttemptID = nil
                setStatus(.failed(classify(error)))
            }
            throw error
        }
    }

    private func establishConnection(attemptID: UUID) async throws {
        guard connectionAttemptID == attemptID else { throw LifecycleError.superseded }

        if let resumeSession, resumeSession.isUsable {
            setStatus(.reconnecting)
            do {
                try await openConnection(
                    mode: .reconnect(sessionID: resumeSession.id),
                    attemptID: attemptID
                )
                return
            } catch LifecycleError.reconnectRejected {
                self.resumeSession = nil
            } catch {
                if lastCloseNotice?.code == .sessionExpired {
                    self.resumeSession = nil
                } else {
                    throw error
                }
            }
        }

        guard let otpSource else { throw LongbridgeError.notConfigured }
        setStatus(.connecting)
        let otp = try await otpSource()
        try Task.checkCancellation()
        guard connectionAttemptID == attemptID else { throw LifecycleError.superseded }
        try await openConnection(mode: .authenticate(otp: otp), attemptID: attemptID)
    }

    private func openConnection(mode: ControlMode, attemptID: UUID) async throws {
        guard connectionAttemptID == attemptID else { throw LifecycleError.superseded }
        disconnect(reason: "replace transport", clearSession: false)
        lastCloseNotice = nil

        let generation = UUID()
        let socket = socketFactory(Self.endpoint)
        task = socket
        connectionGeneration = generation
        authenticated = false
        socket.resume()
        startReceiveLoop(socket, generation: generation)

        do {
            let response = try await send(
                command: mode.command,
                body: mode.body,
                on: socket,
                generation: generation
            )
            guard connectionGeneration == generation, connectionAttemptID == attemptID else {
                throw LifecycleError.superseded
            }
            guard response.status == 0 else {
                switch mode {
                case .authenticate: throw LifecycleError.authenticationRejected(status: response.status)
                case .reconnect: throw LifecycleError.reconnectRejected(status: response.status)
                }
            }

            let session = try LongbridgeMessages.AuthResponse(decoding: response.body)
            resumeSession = ResumeSession(id: session.sessionID, expires: session.expires)
            authenticated = true
            startHeartbeat(generation: generation)
            setStatus(.connected)
            let recovered = hasConnectedBefore
            hasConnectedBefore = true
            if recovered { onRecovered?() }
        } catch {
            disconnect(generation: generation, reason: "control handshake failed", clearSession: false)
            throw error
        }
    }

    private func startReceiveLoop(_ socket: any LongbridgeWebSocket, generation: UUID) {
        receiveLoop?.cancel()
        receiveLoop = Task {
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard case .data(let data) = message else { continue }
                    for packet in try LongbridgePacket.decode(data) {
                        self.handle(packet, on: socket, generation: generation)
                    }
                } catch {
                    self.connectionLost(generation: generation)
                    return
                }
            }
        }
    }

    private func handle(_ packet: LongbridgePacket.Inbound,
                        on socket: any LongbridgeWebSocket, generation: UUID) {
        guard connectionGeneration == generation else { return }
        switch packet {
        case .response(let response):
            pending.removeValue(forKey: response.requestID)?.resume(returning: response)
        case .serverRequest(let command, let requestID, let body):
            if command == LongbridgeCommand.heartbeat.rawValue {
                let reply = LongbridgePacket.encodeResponse(
                    command: command,
                    requestID: requestID,
                    status: 0,
                    body: body
                )
                Task {
                    do {
                        try await socket.send(.data(reply))
                    } catch {
                        self.connectionLost(generation: generation)
                    }
                }
            }
        case .push(let push):
            if push.command == 0 {
                lastCloseNotice = try? LongbridgeMessages.CloseNotice(decoding: push.body)
                if lastCloseNotice?.code == .sessionExpired || lastCloseNotice?.code == .authError {
                    resumeSession = nil
                }
                connectionLost(generation: generation)
            } else {
                onPush?(push.command, push.body)
            }
        }
    }

    private func startHeartbeat(generation: UUID) {
        heartbeatLoop?.cancel()
        heartbeatLoop = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled,
                      self.connectionGeneration == generation,
                      let socket = self.task else { return }
                var writer = ProtobufWriter()
                writer.field(1, int: Int64(Date.now.timeIntervalSince1970))
                do {
                    _ = try await self.send(
                        command: .heartbeat,
                        body: writer.data,
                        on: socket,
                        generation: generation
                    )
                } catch {
                    self.connectionLost(generation: generation)
                    return
                }
            }
        }
    }

    private func connectionLost(generation: UUID) {
        guard connectionGeneration == generation else { return }
        let issue = classify(ProviderError.network(underlying: "Longbridge socket closed"))
        disconnect(generation: generation, reason: "connection lost", clearSession: false)
        setStatus(.failed(issue))
    }

    private func disconnect(generation: UUID? = nil, reason: String, clearSession: Bool) {
        if let generation, connectionGeneration != generation { return }
        receiveLoop?.cancel()
        receiveLoop = nil
        heartbeatLoop?.cancel()
        heartbeatLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connectionGeneration = nil
        authenticated = false
        if clearSession { resumeSession = nil }

        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values {
            continuation.resume(throwing: ProviderError.network(
                underlying: "Longbridge socket closed: \(reason)"
            ))
        }
    }

    private func setStatus(_ newStatus: LongbridgeConnectionStatus) {
        guard status != newStatus else { return }
        status = newStatus
        statusContinuation?.yield(newStatus)
    }

    private func classify(_ error: any Error) -> LongbridgeConnectionIssue {
        if let notice = lastCloseNotice {
            let reason = notice.reason.lowercased()
            if notice.code == .duplicateConnection
                || reason.contains("connection") && reason.contains("limit")
                || reason.contains("online") && reason.contains("limit") {
                return .connectionLimit
            }
            if notice.code == .authError || notice.code == .sessionExpired {
                return .authentication
            }
            if notice.code == .serverError || notice.code == .serverShutdown {
                return .server
            }
        }
        if case LifecycleError.authenticationRejected = error { return .authentication }
        if case LifecycleError.reconnectRejected = error { return .authentication }
        if let providerError = error as? ProviderError {
            switch providerError {
            case .rateLimited: return .rateLimited
            case .network: return .network
            case .badResponse: return .server
            case .clientError, .unsupported, .symbolNotFound: return .authentication
            }
        }
        return .network
    }
}
