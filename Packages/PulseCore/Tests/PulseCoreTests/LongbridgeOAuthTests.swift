import Foundation
import Testing
@testable import PulseCore

@Suite("Longbridge OAuth")
struct LongbridgeOAuthTests {
    @Test func pkceChallengeMatchesRFC7636Vector() {
        // RFC 7636 appendix B golden vector
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(LongbridgeOAuthAuthenticator.pkceChallenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func base64URLIsUnpaddedAndURLSafe() {
        // 0xFB 0xEF 0xFF encodes to "++//" in plain base64
        let encoded = LongbridgeOAuthAuthenticator.base64URL(Data([0xFB, 0xEF, 0xFF]))
        #expect(encoded == "--__")
        // 1 byte would need "==" padding in plain base64
        #expect(LongbridgeOAuthAuthenticator.base64URL(Data([0x00])) == "AA")
    }

    @Test func randomURLSafeIsUniqueAndLongEnough() {
        let a = LongbridgeOAuthAuthenticator.randomURLSafe(32)
        let b = LongbridgeOAuthAuthenticator.randomURLSafe(32)
        #expect(a != b)
        #expect(a.count >= 43) // 32 bytes → 43 unpadded base64 chars
    }

    @Test func extractsCallbackQueryValues() throws {
        let url = try #require(URL(string: "app.pulse.mac.dev://oauth/callback?code=abc123&state=xyz"))
        #expect(LongbridgeOAuthAuthenticator.queryValue("code", in: url) == "abc123")
        #expect(LongbridgeOAuthAuthenticator.queryValue("state", in: url) == "xyz")
        #expect(LongbridgeOAuthAuthenticator.queryValue("missing", in: url) == nil)
    }

    @Test func callbackWithWrongStateIsRejected() async {
        let authenticator = LongbridgeOAuthAuthenticator(redirectScheme: "test.scheme", clientName: "Test")
        let url = URL(string: "test.scheme://oauth/callback?code=abc&state=forged")!
        let consumed = await authenticator.handleCallback(url)
        #expect(!consumed) // no pending flow, and a forged state must never resume one
    }

    @Test func parsesHTTPRequestTarget() {
        let head = "GET /oauth/callback?code=abc&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n"
        #expect(LongbridgeLoopbackServer.requestTarget(fromHead: head) == "/oauth/callback?code=abc&state=xyz")
        #expect(LongbridgeLoopbackServer.requestTarget(fromHead: "POST /x HTTP/1.1\r\n") == nil)
        #expect(LongbridgeLoopbackServer.requestTarget(fromHead: "") == nil)
    }

    /// Full loopback round trip in-process: bind, hit the callback with a real HTTP client,
    /// and expect both the delivered URL and a human-readable success page.
    @Test func loopbackServerDeliversCallbackAndSuccessPage() async throws {
        let port: UInt16 = 41917
        let received = LockedBox<URL>()
        let server = LongbridgeLoopbackServer(port: port, callbackPath: "/oauth/callback") { url in
            received.set(url)
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let callbackURL = URL(string: "http://localhost:\(port)/oauth/callback?code=abc123&state=xyz")!
        let (data, response) = try await URLSession.shared.data(from: callbackURL)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let html = String(decoding: data, as: UTF8.self)
        #expect(html.contains("Pulse")) // page language follows the app setting; content itself is asserted below

        let delivered = try #require(received.get())
        #expect(LongbridgeOAuthAuthenticator.queryValue("code", in: delivered) == "abc123")
        #expect(LongbridgeOAuthAuthenticator.queryValue("state", in: delivered) == "xyz")

        // Unrelated paths must 404 without consuming the flow.
        let (_, other) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(port)/favicon.ico")!)
        #expect((other as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test func loopbackServerShowsCancelPageOnError() async throws {
        let port: UInt16 = 41918 // separate port: tests may run in parallel
        let server = LongbridgeLoopbackServer(port: port, callbackPath: "/oauth/callback") { _ in }
        try await server.start()
        defer { Task { await server.stop() } }

        let denied = URL(string: "http://localhost:\(port)/oauth/callback?error=access_denied&state=xyz")!
        let (data, _) = try await URLSession.shared.data(from: denied)
        let html = String(decoding: data, as: UTF8.self)
        #expect(html.contains("cancelled") || html.contains("授权未完成"))
    }

    @Test func resultPageRendersSingleLanguage() {
        let zh = LongbridgeLoopbackServer.resultPage(denied: false, chinese: true)
        #expect(zh.contains("授权成功"))
        #expect(!zh.contains("Authorized"))
        let en = LongbridgeLoopbackServer.resultPage(denied: true, chinese: false)
        #expect(en.contains("Authorization cancelled"))
        #expect(!en.contains("授权"))
    }
}

/// Tiny thread-safe box for asserting values delivered from @Sendable callbacks.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func set(_ new: Value) {
        lock.withLock { value = new }
    }

    func get() -> Value? {
        lock.withLock { value }
    }
}
