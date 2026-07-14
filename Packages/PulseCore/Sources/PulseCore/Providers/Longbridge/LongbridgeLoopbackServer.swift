import Foundation
import Network

/// One-shot loopback HTTP endpoint for the OAuth redirect: binds 127.0.0.1, waits for the
/// browser to hit the callback path, hands the URL to the flow, and answers with a small
/// human-readable page so the tab never ends up blank. Everything else gets a 404.
actor LongbridgeLoopbackServer {
    enum LoopbackError: Error {
        case portUnavailable(String)
    }

    private let port: UInt16
    private let callbackPath: String
    private let onCallback: @Sendable (URL) -> Void
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<Void, any Error>?

    init(port: UInt16, callbackPath: String, onCallback: @escaping @Sendable (URL) -> Void) {
        self.port = port
        self.callbackPath = callbackPath
        self.onCallback = onCallback
    }

    /// Binds the loopback port; throws when it is unavailable so the flow can fall back to
    /// the custom-scheme redirect.
    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!
        )
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handle(connection) }
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.listenerStateChanged(state) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            startContinuation = continuation
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            startContinuation?.resume()
            startContinuation = nil
        case .failed(let error), .waiting(let error):
            listener?.cancel()
            listener = nil
            startContinuation?.resume(throwing: LoopbackError.portUnavailable(String(describing: error)))
            startContinuation = nil
        default:
            break
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil || buffer.count > 16_384 {
                Task { await self.respond(connection, request: buffer) }
            } else if isComplete {
                connection.cancel()
            } else {
                Task { await self.receiveRequest(connection, buffer: buffer) }
            }
        }
    }

    private func respond(_ connection: NWConnection, request: Data) {
        // Request line: "GET /oauth/callback?code=…&state=… HTTP/1.1"
        let head = String(decoding: request.prefix(2048), as: UTF8.self)
        let target = Self.requestTarget(fromHead: head)

        guard let target, target.hasPrefix(callbackPath),
              let url = URL(string: "http://localhost:\(port)\(target)") else {
            send(connection, response: Self.httpResponse(status: "404 Not Found", html: ""))
            return
        }

        let denied = LongbridgeOAuthAuthenticator.queryValue("error", in: url) != nil
        // The flow starts inside the app, so the page follows the app's language setting.
        let chinese = PulseLocalization.currentLanguageIdentifier.hasPrefix("zh")
        send(connection, response: Self.httpResponse(status: "200 OK", html: Self.resultPage(denied: denied, chinese: chinese)))
        onCallback(url)
    }

    private func send(_ connection: NWConnection, response: Data) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - HTTP bits

    static func requestTarget(fromHead head: String) -> String? {
        guard let requestLine = head.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    static func httpResponse(status: String, html: String) -> Data {
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func resultPage(denied: Bool, chinese: Bool) -> String {
        let mark = denied ? "✕" : "✓"
        let title: String
        let body: String
        if chinese {
            title = denied ? "授权未完成" : "授权成功"
            body = denied ? "你取消了授权,可以关闭此页面。" : "可以关闭此页面并返回 Pulse。"
        } else {
            title = denied ? "Authorization cancelled" : "Authorized"
            body = denied ? "You cancelled the authorization — you can close this tab." : "You can close this tab and return to Pulse."
        }
        return """
        <!doctype html><html lang="\(chinese ? "zh-Hans" : "en")"><head><meta charset="utf-8"><title>Pulse</title><style>
        body { font-family: -apple-system, "PingFang SC", sans-serif; display: flex; min-height: 92vh;
               align-items: center; justify-content: center; background: #ffffff; color: #1d1d1f; }
        @media (prefers-color-scheme: dark) { body { background: #1c1c1e; color: #f5f5f7; } }
        .card { text-align: center; }
        .mark { font-size: 44px; line-height: 1; margin-bottom: 14px; color: \(denied ? "#ff9f0a" : "#30d158"); }
        h2 { margin: 0 0 8px; font-size: 20px; font-weight: 600; }
        p { margin: 0; font-size: 14px; color: #86868b; line-height: 1.7; }
        </style></head><body><div class="card">
        <div class="mark">\(mark)</div>
        <h2>\(title)</h2>
        <p>\(body)</p>
        </div></body></html>
        """
    }
}
