# Pulse — Product Plan & Technical Design

## 1. Product Positioning

> In one sentence: **The market data closest to you — menu bar, widgets, Dynamic Island: look up and see the symbols you care about, and whether you're up or down.**

Design principles (every feature decision is measured against these):

1. **Fast**: from "I want to check" to "I've seen it" in under 1 second, without interrupting whatever you're working on;
2. **Shallow**: browsing only — no trading, no research, no news feed;
3. **Discreet**: watch the market without anyone noticing — compact display, one-click hiding of gain/loss colors (boss-key mindset);
4. **One mental model across platforms**: the Mac menu bar, desktop widgets, iPhone widgets, and the Dynamic Island all show the same watchlist with the same visual language.

---

## 2. MVP (V0.1) Scope

### P0 — Must have

| # | Feature | Notes |
|---|---------|-------|
| 1 | Watchlist | Add via search (ticker / pinyin / name), delete, drag to reorder; supports US / HK / China A-shares / indices / ETFs |
| 2 | Menu bar display | Three modes: **single symbol** (one pinned symbol: `NVDA 188.3 +2.1%`) / **carousel** (rotates through several symbols on a timer) / **compact** (up/down indicator only); gain/loss colors selectable: red-up/green-down (A-share convention, the default) or green-up/red-down |
| 3 | Quote popover (opens on menu bar click) | Watchlist rows: name, last price, change %, mini sparkline; click any row to expand details |
| 4 | Detail charts | **Intraday chart + daily / weekly / monthly candlestick switching** (candlesticks are the core differentiator vs. competitors); shows OHLC and volume |
| 5 | Refresh strategy | Configurable refresh interval (5s/15s/30s/60s); **trading-session aware**: refresh during market hours per each market's trading calendar, stop when markets are closed (saves power and bandwidth, avoids rate limiting) |
| 6 | Basic settings | Launch at login, gain/loss colors, menu bar display mode, data source selection |

### P1 — Within the MVP if time allows

- One-click stealth mode (the menu bar becomes an innocuous icon; the popover requires an extra click before showing any numbers)
- Pre/post-market prices (US stocks)
- Multi-currency labels (USD / HKD / CNY symbols)

### Explicitly out of scope (this version)

- ❌ Cost basis / P&L (the core of V0.2 — but the data model reserves the fields now)
- ❌ Price alerts (V0.2)
- ❌ Any widgets / iOS (V0.3+)
- ❌ News, earnings, fundamentals, trading

### MVP acceptance criteria

Dogfood it for a week: during working hours, don't open any other quote app — cover day-to-day watching of the watchlist with Pulse alone, and feel no urge to uninstall it.

---

## 3. Version Roadmap

```
V0.1  Mac menu bar MVP       Watchlist + menu bar quotes + candlestick popover
V0.2  P&L perspective        Enter cost basis → menu bar shows position P&L amount / percentage directly; price alerts
V0.3  Mac desktop widgets    WidgetKit desktop / Notification Center widgets (watchlist overview, single-symbol candlestick card)
V0.4  Polish & distribution  Sparkle self-updates or the Mac App Store; website
V1.0  iOS                    iPhone app (watchlist synced via iCloud) + Home/Lock Screen widgets + Dynamic Island watching
                             (Dynamic Island mode: pick one stock and start a "watch session" Live Activity,
                             refreshed in real time during trading hours)
```

Product shape of cost basis / P&L (V0.2 preview; it affects the V0.1 data model):

- Each symbol can record multiple lots (cost price + quantity), stored locally, no brokerage connection;
- A new "P&L mode" for the menu bar: shows `Today +¥1,240` or `NVDA +12.3%`;
- Each watchlist row shows: last price, today's change, position P&L;
- The candlestick chart draws a horizontal **cost line**, so you can see at a glance where the current price sits relative to your cost.

---

## 4. Technology Choices

### Conclusion: fully native Swift/SwiftUI, single repository with multiple targets

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Language | Swift 6 | The only option that covers menu bar / WidgetKit / ActivityKit all at once |
| UI | SwiftUI + `MenuBarExtra` (`.window` style) | Native menu bar API; the same view code is reused on iOS / widgets |
| Charts | **Swift Charts** | Native and lightweight; `RectangleMark + RuleMark` is enough for candlesticks; supported across macOS / iOS / widgets |
| Concurrency / networking | Swift Concurrency + URLSession | No third-party dependencies |
| Storage | Watchlist / settings → `UserDefaults` (**in an App Group container from day 1**, paving the way for widgets); candle cache → JSON on disk; V0.2 cost data → SwiftData |
| Minimum OS | macOS 26+ for the app (Liquid Glass design language; see the toolchain baseline below). The PulseCore/PulseUI packages keep a lower floor (macOS 14 / iOS 17) so future clients can reuse them; the Dynamic Island needs iOS 16.1+, stable API since 17 |
| Dependency management | Swift Package Manager, as close to zero third-party dependencies as possible |
| Distribution | Local builds during development → decide in V0.4 between Developer ID + Sparkle or the Mac App Store |

**Why not Electron/Tauri**: poor menu bar experience (memory, startup time), and no way whatsoever to build WidgetKit widgets or Dynamic Island Live Activities — the multi-platform roadmap rules out non-native options outright.

### Project structure (the key design for cross-platform reuse)

```
Pulse/
├── Packages/
│   ├── PulseCore/          # Pure Swift package, no UI — the core shared by all platforms
│   │   ├── Models/         #   Symbol, Quote, Candle, Watchlist, Position (reserved)
│   │   ├── Providers/      #   QuoteProvider protocol + Yahoo/Tencent/Longbridge implementations
│   │   ├── Market/         #   Trading calendars, session logic, market metadata
│   │   └── Store/          #   Watchlist persistence (App Group), candle cache, refresh scheduler
│   └── PulseUI/            # Shared SwiftUI components: candlestick chart, intraday chart, sparkline, gain/loss colors
├── PulseMac/               # macOS menu bar app (MenuBarExtra, LSUIElement=true)
├── PulseWidgets/           # (V0.3) macOS WidgetKit extension
├── PulseiOS/               # (V1.0) iPhone app + widgets + Live Activity
└── docs/
```

### Core data layer abstraction (see [PROVIDERS.md](PROVIDERS.md), split into its own document)

The data source is Pulse's foundation and its biggest external risk, and **user-extensible data sources are an explicit product direction**, so the provider architecture gets a dedicated design:

- The `QuoteProvider` protocol (search / quotes / candles / optional quoteStream) + `ProviderDescriptor` capability self-description (market coverage, delay, rate limits, required credentials);
- `CompositeProvider`: per-market routing + health-based circuit breaking and failover + multi-source data composition (A-share prices from Tencent, candles from Yahoo);
- `RefreshEngine` (an actor) as the single scheduler: providers only decide *how* to fetch, never *when* to fetch;
- A **four-tier plugin system**: built-in Swift providers → declarative JSON manifests (zero-code integration of new REST sources, V0.3) → JavaScriptCore script plugins (V1.x) → process-level plugins (long term); plugin bundle format `.pulseprovider`, validated by the built-in contract tests on import;
- The protocol, descriptors, and contract tests are **finalized in V0.1** — they are the foundation for every later extension tier.

### Toolchain baseline

- **Build baseline: SDK 26 release APIs; no dependency on any SDK 27 beta API**;
- **Deployment target macOS 26+**: a product decision to adopt the Liquid Glass design language (`glassEffect` / `GlassEffectContainer` / `.buttonStyle(.glass)` are all 26+ APIs). macOS 26 is the current release, and we don't maintain fallback branches for older systems. Glass is used only for the floating control layer (header buttons, search field, gain/loss capsules); the content layer (lists, charts) stays plain;
- Watchlist drag-to-reorder uses `List` + `onMove`, deletion uses the context menu — all stable APIs.

### SDK 27 outlook (beta, shipping this fall; a migration checklist for the eventual toolchain upgrade, not a basis for current design)

- `@State` changes from a property wrapper to a macro: views with custom initializers have a source break (consult `state-macro.md` in the swiftui-whats-new-27 skill at that point; the fix is *not* reordering the assignments);
- Deeply branched closures inside `Chart` trigger type-check timeouts under SDK 27 — **extracting mark branches into `@ChartContentBuilder` private functions** is good structure anyway; write it that way now for zero migration cost later;
- `.reorderable()` (drag-to-reorder in any container) and `swipeActionsContainer()` (swipe actions in any container) can be adopted as experience enhancements once 27 ships, gated with `#available`.

### Testing & engineering baseline

- Unit tests use **Swift Testing** (`@Test` / `#expect` / parameterized cases), not XCTest; focus areas: provider symbol format conversion, JSON fixture replay, and the provider contract test suite;
- Run the audit-xcode-security-settings baseline at project creation (warning set, static analysis, Enhanced Security);
- Credentials always go in the Keychain; plugin content is treated as untrusted input.

---

## 5. Key Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Yahoo's unofficial API gets rate-limited or breaks (tightened repeatedly in 2025) | Dual-source redundancy + exponential backoff + local caching; everything goes through the `QuoteProvider` abstraction, so the whole source can be swapped at any time |
| Widgets can't be realtime (system refresh budget of ~40–70 updates/day) | Position widgets as "low-frequency glances" in the product design, and label the last update time; realtime needs are served by the menu bar / Dynamic Island |
| Dynamic Island 8-hour limit + high-frequency updates require push | Design it as a "watch session": started manually/automatically at the open, ended at the close; request the `frequent-updates` entitlement |
| Market data licensing / App Review once distributed | Use free sources for the personal-use and free stages; switch to licensed sources like AllTick/iTick before commercialization (the interface is already abstracted, keeping the cost contained) |
| Yahoo's A-share data is delayed 15 minutes | Intraday prices are overridden with Tencent's realtime snapshots; candles still come from Yahoo |

---

## 6. MVP Milestones (estimates)

| Milestone | Scope | Estimate |
|-----------|-------|----------|
| M1 | Project scaffolding: Xcode project + PulseCore package + MenuBarExtra shell + App Group | 0.5 day |
| M2 | Data layer: QuoteProvider protocol + descriptors + Yahoo/Tencent implementations + composite routing + **contract test suite** (live-endpoint smoke tests + fixture replay) | 2 days |
| M3 | Three menu bar display modes + refresh scheduling (trading-session aware) | 1 day |
| M4 | Popover: watchlist + search-to-add + sparkline | 1–2 days |
| M5 | Detail charts: intraday + daily/weekly/monthly candlesticks (Swift Charts) | 1–2 days |
| M6 | Settings pane + launch at login + polish | 1 day |

Roughly **6–8 development days** in total to reach a self-usable MVP.
