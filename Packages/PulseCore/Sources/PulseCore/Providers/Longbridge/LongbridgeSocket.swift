import Foundation

/// One persistent connection to the Longbridge quote gateway (the account allows a single
/// long link). Owns the WebSocket lifecycle: OTP auth, request/response pairing, heartbeats,
/// and lazy reconnection on the next request after a drop.
actor LongbridgeSocket {
    static let endpoint = URL(string: "wss://openapi-quote.longbridge.com/v2?version=1&codec=1&platform=9")!

    /// Produces a one-time socket password. The concrete auth mode (signed API-key HTTP or
    /// an OAuth bearer) lives entirely behind this closure.
    typealias OTPSource = @Sendable () async throws -> String

    private var otpSource: OTPSource?
    private var onPush: (@Sendable (UInt8, Data) -> Void)?
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var heartbeatLoop: Task<Void, Never>?
    private var nextRequestID: UInt32 = 1
    private var pending: [UInt32: CheckedContinuation<LongbridgePacket.Response, any Error>] = [:]
    private let session: URLSession
    private let requestTimeout: Duration = .seconds(10)

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func updateOTPSource(_ source: OTPSource?) {
        otpSource = source
        disconnect(reason: "auth changed")
    }

    /// Receives business push packets (quote subscriptions). Control pushes stay internal.
    func setPushHandler(_ handler: (@Sendable (UInt8, Data) -> Void)?) {
        onPush = handler
    }

    // MARK: - Requests

    func request(_ command: LongbridgeCommand, body: Data) async throws -> Data {
        try await ensureConnected()
        let response = try await send(command: command, body: body)
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

    /// Sends one framed request and waits for the paired response, bounded by `requestTimeout`
    /// so a dropped connection can never leave a caller suspended forever.
    /// The continuation is registered before the frame goes out — the response can otherwise
    /// arrive on the receive loop before registration and be dropped.
    private func send(command: LongbridgeCommand, body: Data) async throws -> LongbridgePacket.Response {
        guard let task else { throw LongbridgeError.socket("not connected") }
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
                    try await task.send(.data(frame))
                } catch {
                    self.fail(requestID, with: ProviderError.network(underlying: error.localizedDescription))
                    self.connectionLost()
                }
            }
        }
    }

    private func fail(_ requestID: UInt32, with error: any Error) {
        pending.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    // MARK: - Connection lifecycle

    private func ensureConnected() async throws {
        if task != nil { return }
        guard let otpSource else { throw LongbridgeError.notConfigured }

        // OTP is single-use; the socket authenticates with it right after connecting.
        let otp = try await otpSource()

        let socketTask = session.webSocketTask(with: Self.endpoint)
        socketTask.resume()
        task = socketTask
        startReceiveLoop(socketTask)

        do {
            // Overnight quotes are opt-in per connection; without this metadata the server
            // omits over_night_quote from pulls and never pushes overnight ticks.
            let body = LongbridgeMessages.authRequest(otp: otp, metadata: ["need_over_night_quote": "true"])
            let response = try await send(command: .auth, body: body)
            guard response.status == 0 else {
                throw LongbridgeError.socket("auth rejected with status \(response.status)")
            }
            _ = try LongbridgeMessages.AuthResponse(decoding: response.body)
        } catch {
            disconnect(reason: "auth failed")
            throw error
        }
        startHeartbeat()
    }

    private func startReceiveLoop(_ socketTask: URLSessionWebSocketTask) {
        receiveLoop = Task {
            while !Task.isCancelled {
                do {
                    let message = try await socketTask.receive()
                    guard case .data(let data) = message else { continue }
                    for packet in try LongbridgePacket.decode(data) {
                        self.handle(packet, on: socketTask)
                    }
                } catch {
                    self.connectionLost()
                    return
                }
            }
        }
    }

    private func handle(_ packet: LongbridgePacket.Inbound, on socketTask: URLSessionWebSocketTask) {
        switch packet {
        case .response(let response):
            pending.removeValue(forKey: response.requestID)?.resume(returning: response)
        case .serverRequest(let command, let requestID, let body):
            // Heartbeat contract: echo the body back with the same request id.
            if command == LongbridgeCommand.heartbeat.rawValue {
                let reply = LongbridgePacket.encodeResponse(command: command, requestID: requestID, status: 0, body: body)
                Task { try? await socketTask.send(.data(reply)) }
            }
        case .push(let push):
            // cmd 0 is the server's close notice; everything else is subscription data.
            if push.command == 0 {
                connectionLost()
            } else {
                onPush?(push.command, push.body)
            }
        }
    }

    private func startHeartbeat() {
        heartbeatLoop = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                var writer = ProtobufWriter()
                writer.field(1, int: Int64(Date.now.timeIntervalSince1970))
                _ = try? await self.request(.heartbeat, body: writer.data)
            }
        }
    }

    private func connectionLost() {
        disconnect(reason: "connection lost")
    }

    private func disconnect(reason: String) {
        receiveLoop?.cancel()
        receiveLoop = nil
        heartbeatLoop?.cancel()
        heartbeatLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values {
            continuation.resume(throwing: ProviderError.network(underlying: "Longbridge socket closed: \(reason)"))
        }
    }
}
