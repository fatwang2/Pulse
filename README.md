# Pulse

**Glanceable market data for the macOS menu bar.**

Pulse is a lightweight market-watching app, not a trading terminal. It solves exactly one problem: seeing how the symbols you care about are doing — and whether your positions are up or down — in the shortest possible time, without leaving what you're working on.

![Pulse watchlist share image](assets/readme/pulse-menu-bar.png)

## Features

- **Menu bar ticker**: icon-only by default (discreet); optionally show quotes as a pinned single symbol (`NVDA 188.3 +2.1%`) or a carousel rotating through your watchlist
- **Watchlist** supporting US stocks, Hong Kong stocks, China A-shares, cryptocurrencies, indices, and ETFs — add by ticker, name, or pinyin search
- **Position tracking**: quantity, cost basis, market value, daily P&L, and total P&L
- **Quote detail view**: price, change, OHLC, volume, turnover, realtime / delayed status, quote source, and market-specific timestamp in a dense menu-bar layout
- **Charts**: realtime Tencent intraday lines for China A-shares, plus Yahoo-backed daily / weekly / monthly candlesticks with OHLC and volume
- **Share images**: copy a branded, mobile-friendly watchlist image that follows the current metric selection and adapts to list length
- **Multi-provider data layer**: providers are routed per market, cached to reduce duplicate requests, and fail over automatically when one is rate-limited or down
- **Trading-session-aware refresh**: polls only while each market is open, following its trading calendar — saving power and avoiding rate limits
- **Language control**: follows the system language when possible, with manual switching between English and Simplified Chinese

## Installation

Download the latest `Pulse-*.dmg` from [GitHub Releases](https://github.com/fatwang2/Pulse/releases), open it, and drag `Pulse.app` to Applications before launching. The `Pulse-*.zip` asset is used by Sparkle for automatic updates.

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

# Unit tests plus provider contracts against the live endpoints
PULSE_LIVE_TESTS=1 swift test
```

## Architecture

- **`Packages/PulseCore`** — pure Swift, no UI: models, data providers, trading calendars, persistence, and the refresh scheduler. Shared across Mac / iOS / widget targets.
- **`Packages/PulseUI`** — shared SwiftUI components: candlestick chart, intraday chart, sparkline, gain/loss colors.
- **`PulseMac`** — the macOS menu bar app (`MenuBarExtra`, `LSUIElement=true`).

All market data flows through the `QuoteProvider` protocol abstraction. A `CompositeProvider` routes requests per market and candle period, caches recent responses, breaks the circuit on unhealthy providers, and composes data from multiple sources (e.g. realtime A-share quotes and intraday lines from Tencent, historical candles and cryptocurrency coverage from Yahoo).

Quotes carry their active source and source-specific delay metadata through the app. The watchlist footer shows the app refresh time, while each symbol detail view shows that symbol's realtime / delayed status, active source, and market timestamp with the relevant time basis.

## Data Sources & Disclaimer

Pulse currently uses **free, unofficial** quote endpoints from Yahoo Finance and Tencent. These come with no SLA and may be rate-limited or change without notice. Quote delay varies by provider and market; delayed sources are labeled in the UI when the provider exposes that metadata. All data is for reference only and is **not investment advice**.

## License

[MIT](LICENSE)
