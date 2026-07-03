# Pulse — Data Source (Provider) Architecture

> Goal: the market data source is Pulse's foundation and its biggest external risk (rate limiting, breakage, licensing).
> Design principle: **the core knows about no concrete data source** — every source (including ones users write themselves in the future) is just one implementation of `QuoteProvider`.

## 1. Core Protocol

```swift
// PulseCore/Providers/QuoteProvider.swift
public protocol QuoteProvider: Sendable {
    /// Self-describing metadata: drives routing, capability negotiation, and the settings UI
    var descriptor: ProviderDescriptor { get }

    /// Search for symbols (ticker / name / pinyin)
    func search(_ query: String) async throws -> [SymbolInfo]

    /// Batched quote snapshots (the primary data for the menu bar and list views)
    func quotes(for symbols: [SymbolID]) async throws -> [Quote]

    /// Candles / intraday (period: .minute1 / .day / .week / .month ...)
    func candles(for symbol: SymbolID, period: CandlePeriod,
                 count: Int) async throws -> [Candle]

    /// Realtime streaming (optional capability; unsupported by default)
    func quoteStream(for symbols: [SymbolID])
        -> AsyncThrowingStream<Quote, any Error>?
}

public extension QuoteProvider {
    func quoteStream(for symbols: [SymbolID])
        -> AsyncThrowingStream<Quote, any Error>? { nil }
}
```

### Capability self-description (the basis for routing and failover)

```swift
public struct ProviderDescriptor: Codable, Sendable {
    public var id: String                      // "yahoo" / "tencent" / "plugin.my-source"
    public var name: String                    // Display name
    public var markets: Set<Market>            // .us / .hk / .cnA / .crypto ...
    public var capabilities: Set<Capability>   // .search / .quotes / .candles / .streaming / .prePost
    public var delay: [Market: Duration]       // Declared data delay (A-shares 15 min? realtime?)
    public var rateLimit: RateLimitPolicy?     // Self-declared rate limit (the scheduler throttles accordingly)
    public var credentials: [CredentialField]  // Credentials the user must provide (e.g. a Longbridge key)
}
```

### Routing and resilience: `CompositeProvider`

The core only ever talks to a single `CompositeProvider`, which does three things:

1. **Per-market routing**: each market gets a provider priority chain (adjustable by the user in settings), e.g.
   `A-shares: [tencent, yahoo]`, `US: [yahoo, tencent]`, `all (if configured): [longbridge, ...]`;
2. **Health-based failover**: a network-level failure / 5xx / rate limiting → trip the circuit breaker for a while, automatically fall through to the next provider, and switch back after recovery.
   **Note: request-level 4xx errors do not trip the breaker** — lesson learned: Yahoo's search endpoint does not support Chinese queries (it returns 400 "Invalid Search Query");
   treating that as a fault would wrongly take down all of Yahoo (including its unique candle capability). Chinese/pinyin search is handled by Tencent's smartbox, and a Yahoo 400 is treated as an empty result;
3. **Data composition**: prices from the low-latency source, candles from the source with the most complete data (e.g. intraday A-share prices from Tencent, candles from Yahoo).

Every request flows through the single `RefreshEngine` (an actor): scheduling by market trading sessions, throttling, deduplication, caching — **providers only decide "how to fetch", never "when to fetch"**. This boundary is also the foundation of future plugin safety: plugin code cannot bypass the scheduler and hammer an endpoint.

---

## 2. Extensibility: A Four-Tier Plugin System

User-extensible data sources are an explicit product direction (Longbridge/Futu/IB users, Wind users, crypto exchanges, even corporate intranet data... official coverage of everything is impossible). Four tiers, from easy to hard and from safe to powerful, rolled out version by version:

### Tier 0 — Built-in providers (Swift, officially maintained)

`YahooProvider` / `TencentProvider` / `LongbridgeProvider`. Each is implemented as an `actor` (holding mutable state internally — cookie/crumb caches, rate-limit counters — so thread safety comes for free).

### Tier 1 — Declarative manifest providers (feasible in V0.x) ⭐ the recommended primary extension path

Most quote REST APIs differ only in "URL format + field names". Build a generic `ManifestProvider` engine that consumes a JSON description file to integrate a new source — **zero code, inherently safe, and usable on all three platforms (Mac/iOS/widgets)**:

```jsonc
// my-source.pulseprovider/manifest.json
{
  "id": "my-source",
  "name": "My Quote API",
  "version": 1,
  "markets": ["us", "hk"],
  "delay": { "us": 0, "hk": 900 },
  "credentials": [{ "key": "apiKey", "label": "API Key", "secure": true }],
  "symbolFormat": { "hk": "{code:05d}.HK", "us": "{code}" },   // 700 → 00700.HK
  "endpoints": {
    "quotes": {
      "url": "https://api.example.com/v1/snapshot?symbols={symbols}&key={apiKey}",
      "batch": 50,
      "map": {                       // JSON field mapping (dot paths + array wildcards)
        "items": "$.data[*]",
        "symbol": "code", "price": "last", "prevClose": "pc",
        "high": "h", "low": "l", "volume": "vol", "timestamp": "ts"
      }
    },
    "candles": {
      "url": "https://api.example.com/v1/kline?symbol={symbol}&period={period}&count={count}",
      "periodMap": { "day": "1d", "week": "1wk", "minute1": "1m" },
      "map": { "items": "$.data.candles[*]", "time": "0", "open": "1",
               "high": "2", "low": "3", "close": "4", "volume": "5" }
    }
  }
}
```

The engine handles URL template rendering, batch splitting, field mapping, and unit/time zone normalization. Credentials are stored in the Keychain; `{apiKey}` is only injected at request time. **No code execution, so zero App Store review risk.**

### Tier 2 — Script providers (JavaScriptCore, V1.x)

For cases a manifest cannot express: request signing, non-JSON formats (Tencent's endpoint is semicolon-delimited text), multi-step requests. Approach: the user drops a JS file into the plugin bundle, implementing the same three functions:

```js
// my-source.pulseprovider/provider.js
async function quotes(symbols, ctx) {
  const text = await ctx.fetch(`https://qt.gtimg.cn/q=${symbols.join(',')}`);
  return parseGtimg(text);   // Return the unified Quote structure
}
async function candles(symbol, period, count, ctx) { /* ... */ }
async function search(query, ctx) { /* ... */ }
```

- The host uses **JavaScriptCore** (a system framework on both macOS and iOS; no third-party dependency);
- Sandbox boundary: scripts get **only** `ctx.fetch` (throttled by the RefreshEngine, with a declarable domain allowlist), `ctx.log`, and `ctx.credentials` — no file system, no capabilities beyond that;
- Compliance notes: direct Mac distribution (Developer ID) has no restrictions; on the App Store, follow the "user-created scripts" model (Scriptable is the precedent) — **no built-in online plugin store distribution**; offer "import from file" instead.

### Tier 3 — Process-level plugins (long-term consideration, Mac only)

xbar-style executables or ExtensionKit `.appex` bundles — capable of WebSocket push and of connecting to local brokerage gateways (IB Gateway!). Powerful but heavy: complex security model, unavailable on iOS, and very likely incompatible with the Mac App Store sandbox. **Build it only once the community actually asks for it**; the protocol layer is already compatible (to the core, a process plugin is still just a `QuoteProvider`).

### Plugin bundle format and distribution

```
my-source.pulseprovider/        ← a directory is a plugin (modeled on .app bundles)
├── manifest.json               # Required: metadata + Tier 1 declarative endpoints (optional)
├── provider.js                 # Optional: Tier 2 script (takes precedence over declarative endpoints if present)
└── icon.png                    # Optional
```

- Installation: drag into the settings pane / double-click to open; stored under `Application Support/Pulse/Providers/`;
- Community distribution: a `pulse-providers` GitHub repository collecting community plugins (following the xbar / Raycast extensions model);
- **Conformance contract tests**: PulseCore ships a Provider Conformance Test suite (parameterized Swift Testing cases: field completeness, time zone correctness, batching behavior, error semantics). Built-in providers run it, and plugins run it at import time for validation, with specific error messages on failure. This test suite doubles as the "specification document" of the plugin ecosystem.

---

## 3. Swift Engineering Details (conclusions from researching the local skills)

### Swift 6 concurrency model

- All models (`Quote` / `Candle` / `SymbolInfo`): `struct + Codable + Sendable`;
- Providers with internal state are `actor`s; stateless ones are `struct`s;
- `RefreshEngine` is the only scheduling actor; the UI layer reads data through an `@Observable` `MarketStore`;
- Streaming goes uniformly through `AsyncThrowingStream`; polling and push look identical to the UI.

### Toolchain baseline and SDK 27 outlook

**Baseline: build with the current release Xcode (SDK 26), app deployment target macOS 26+ (Liquid Glass), no dependency on any SDK 27 beta API.** The PulseCore/PulseUI packages keep a macOS 14 floor for future reuse. All UI interactions use stable APIs: drag-to-reorder via `List.onMove`, deletion via context menu.

SDK 27 (beta, shipping this fall) migration checklist for the eventual toolchain upgrade — consult the corresponding swiftui-whats-new-27 skill references at that time:

| Item | Action at that time |
|------|---------------------|
| `@State` becomes a macro; source break for assignments in init | Fix per `state-macro.md` (not by reordering the assignments) |
| Deep branches inside `Chart` hit type-check timeouts under SDK 27 | Extract candlestick mark branches into `@ChartContentBuilder` private functions **now** (good structure anyway) — zero cost later |
| `.reorderable()` / `swipeActionsContainer()` | Adopt as experience enhancements once 27 ships, gated with `#available` |

### Testing and security

- **Swift Testing** (`@Test` / `#expect` / parameterized cases), not XCTest (the same direction as the test-modernizer skill); focus: parameterized symbol-format conversion cases for each provider + recorded JSON fixture replay + the contract test suite above;
- Run the **audit-xcode-security-settings** skill baseline once at project creation (compiler warnings, static analysis, Enhanced Security);
- Credentials always in the Keychain; plugin directory contents are treated as untrusted input (defensive manifest parsing).

### UI component resources

ShipSwift recipes (add-component / build-feature skills): the local recipe server is not connected; restore it with `npx skills add signerlabs/shipswift-skills` when needed. Its chart recipes (Line/Bar/Area/Heatmap) can serve as sparkline references, but candlesticks remain hand-drawn (Swift Charts `RectangleMark` + `RuleMark`).

---

## 4. Delivery Cadence

| Version | Provider-side deliverables |
|---------|---------------------------|
| V0.1 (MVP) | `QuoteProvider` protocol + Yahoo/Tencent built-ins + `CompositeProvider` routing & failover + contract test suite + **data source list in settings (individually disableable, paving the way for custom sources)** |
| V0.2 | `LongbridgeProvider` (user-supplied key) + Keychain credential framework |
| V0.3 | **Tier 1 manifest engine** + plugin bundle format + import UI + contract tests on import |
| V1.x | Tier 2 JS script engine + the `pulse-providers` community repository |
| Long term | Tier 3 process plugins (as demand warrants) |

The key point: **the protocol, descriptors, and contract tests are finalized in V0.1** — they are the foundation of every later tier. The extra half-day spent here during the MVP buys out a future refactor.
