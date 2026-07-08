# Pulse

**Glanceable market data for the macOS menu bar.**

Pulse is a lightweight market-watching app, not a trading terminal. It solves exactly one problem: seeing how the symbols you care about are doing — and whether your positions are up or down — in the shortest possible time, without leaving what you're working on.

## Features

- **Menu bar ticker**: icon-only by default (discreet); optionally show quotes as a pinned single symbol (`NVDA 188.3 +2.1%`) or a carousel rotating through your watchlist
- **Watchlist** supporting US stocks, Hong Kong stocks, and China A-shares, plus indices and ETFs — add by ticker, name, or pinyin search
- **Position tracking**: quantity, cost basis, market value, daily P&L, and total P&L, with a compact one-currency portfolio summary in the watchlist
- **Quote detail view**: price, change, OHLC, volume, turnover, quote source, market timestamp, and realtime / delayed status in a dense menu-bar layout
- **Charts**: market-aware intraday line chart plus daily / weekly / monthly candlesticks with OHLC and volume
- **Multi-provider data layer**: providers are routed per market and fail over automatically when one is rate-limited or down
- **Trading-session-aware refresh**: polls only while each market is open, following its trading calendar — saving power and avoiding rate limits

## Building

Requires **Xcode 26+** and [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Pulse.xcodeproj` is generated from `project.yml` and is not checked in.

```bash
# Generate the Xcode project and build
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme PulseMac -configuration Debug build
```

Tests live in the `PulseCore` package:

```bash
# Unit tests (includes Tencent/Yahoo parsing via recorded fixtures)
cd Packages/PulseCore && swift test

# Provider contract tests against the live endpoints
PULSE_LIVE_TESTS=1 swift test --filter ProviderContractTests
```

## Architecture

- **`Packages/PulseCore`** — pure Swift, no UI: models, data providers, trading calendars, persistence, and the refresh scheduler. Shared across Mac / iOS / widget targets.
- **`Packages/PulseUI`** — shared SwiftUI components: candlestick chart, intraday chart, sparkline, gain/loss colors.
- **`PulseMac`** — the macOS menu bar app (`MenuBarExtra`, `LSUIElement=true`).

All market data flows through the `QuoteProvider` protocol abstraction. A `CompositeProvider` routes requests per market, breaks the circuit on unhealthy providers, and composes data from multiple sources (e.g. realtime A-share prices from Tencent, candles from Yahoo).

Quotes carry their active source and source-specific delay metadata through the app. The watchlist footer shows the app refresh time, while each symbol detail view shows that symbol's market timestamp and whether the active source is realtime or delayed.

## Data Sources & Disclaimer

Pulse currently uses **free, unofficial** quote endpoints from Yahoo Finance and Tencent. These come with no SLA and may be rate-limited or change without notice. Quote delay varies by provider and market; delayed sources are labeled in the UI when the provider exposes that metadata. All data is for reference only and is **not investment advice**.

## License

[MIT](LICENSE)
