import Foundation
import Testing
@testable import PulseCore

@Suite("Longbridge socket lifecycle", .serialized)
struct LongbridgeSocketTests {
    @Test func concurrentRequestsShareOneAuthenticatedConnection() async throws {
        let factory = TestSocketFactory()
        let otpCalls = AsyncCounter()
        let socket = LongbridgeSocket { _ in factory.makeSocket() }
        await socket.updateOTPSource {
            await otpCalls.increment()
            try await Task.sleep(for: .milliseconds(80))
            return "otp-1"
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = try await socket.request(.querySecurityQuote, body: Data())
                }
            }
            try await group.waitForAll()
        }

        #expect(await otpCalls.value == 1)
        #expect(factory.socketCount == 1)
        let commands = try #require(factory.sockets.first).sentCommands
        #expect(commands.filter { $0 == LongbridgeCommand.auth.rawValue }.count == 1)
        #expect(commands.first == LongbridgeCommand.auth.rawValue)
        #expect(commands.filter { $0 == LongbridgeCommand.querySecurityQuote.rawValue }.count == 20)
    }

    @Test func reconnectReusesServerSessionWithoutMintingAnotherOTP() async throws {
        let factory = TestSocketFactory()
        let otpCalls = AsyncCounter()
        let recoveries = AsyncCounter()
        let socket = LongbridgeSocket { _ in factory.makeSocket() }
        await socket.updateOTPSource {
            await otpCalls.increment()
            return "otp-1"
        }
        await socket.setRecoveryHandler {
            Task { await recoveries.increment() }
        }

        _ = try await socket.request(.querySecurityQuote, body: Data())
        await socket.resetConnection()
        _ = try await socket.request(.querySecurityQuote, body: Data())

        #expect(await otpCalls.value == 1)
        #expect(factory.socketCount == 2)
        let second = try #require(factory.sockets.last)
        #expect(second.sentCommands.first == LongbridgeCommand.reconnect.rawValue)
        await recoveries.wait(until: 1)
        #expect(await recoveries.value == 1)
    }

    @Test func reconnectAndCloseMessagesRoundTrip() throws {
        var reconnect = ProtobufReader(LongbridgeMessages.reconnectRequest(
            sessionID: "session-1",
            metadata: ["need_over_night_quote": "true"]
        ))
        let reconnectField = try #require(try reconnect.nextField())
        #expect(reconnectField.number == 1)
        #expect(reconnectField.value.string == "session-1")
        let metadataField = try #require(try reconnect.nextField())
        #expect(metadataField.number == 2)

        var close = ProtobufWriter()
        close.field(1, int: 6)
        close.field(2, string: "connections limitation is hit")
        let notice = try LongbridgeMessages.CloseNotice(decoding: close.data)
        #expect(notice.code == .duplicateConnection)
        #expect(notice.reason == "connections limitation is hit")
    }
}

private actor AsyncCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }

    func wait(until target: Int) async {
        while value < target {
            await Task.yield()
        }
    }
}

private final class TestSocketFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TestWebSocket] = []

    var sockets: [TestWebSocket] {
        lock.withLock { storage }
    }

    var socketCount: Int {
        lock.withLock { storage.count }
    }

    func makeSocket() -> TestWebSocket {
        let socket = TestWebSocket()
        lock.withLock { storage.append(socket) }
        return socket
    }
}

private final class TestWebSocket: LongbridgeWebSocket, @unchecked Sendable {
    typealias Message = URLSessionWebSocketTask.Message

    private let lock = NSLock()
    private var messages: [Result<Message, any Error>] = []
    private var receiver: CheckedContinuation<Message, any Error>?
    private var commandStorage: [UInt8] = []
    private var isCancelled = false

    var sentCommands: [UInt8] {
        lock.withLock { commandStorage }
    }

    func resume() {}

    func send(_ message: Message) async throws {
        guard case .data(let frame) = message else { return }
        let command = frame[frame.startIndex + 1]
        let requestID = frame[(frame.startIndex + 2)..<(frame.startIndex + 6)]
            .reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        lock.withLock { commandStorage.append(command) }

        var body = Data()
        if command == LongbridgeCommand.auth.rawValue || command == LongbridgeCommand.reconnect.rawValue {
            var session = ProtobufWriter()
            session.field(1, string: "session-1")
            session.field(2, int: Int64(Date.now.addingTimeInterval(300).timeIntervalSince1970))
            body = session.data
        }
        enqueue(.success(.data(LongbridgePacket.encodeResponse(
            command: command,
            requestID: requestID,
            status: 0,
            body: body
        ))))
    }

    func receive() async throws -> Message {
        try await withCheckedThrowingContinuation { continuation in
            let queued: Result<Message, any Error>? = lock.withLock {
                if !messages.isEmpty { return messages.removeFirst() }
                if isCancelled { return .failure(CancellationError()) }
                receiver = continuation
                return nil
            }
            if let queued { continuation.resume(with: queued) }
        }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let waiting: CheckedContinuation<Message, any Error>? = lock.withLock {
            isCancelled = true
            defer { receiver = nil }
            return receiver
        }
        waiting?.resume(throwing: CancellationError())
    }

    private func enqueue(_ result: Result<Message, any Error>) {
        let waiting: CheckedContinuation<Message, any Error>? = lock.withLock {
            if let receiver {
                self.receiver = nil
                return receiver
            }
            messages.append(result)
            return nil
        }
        waiting?.resume(with: result)
    }
}
