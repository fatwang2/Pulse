# Pulse — Market Research (2026-07)

## 1. Competitive Analysis

### 1. Mac menu bar tickers (direct competitors)

| Product | Price | Core features | Gap (our opportunity) |
|---------|-------|---------------|----------------------|
| **StocksBar** (menu bar stock/fund watcher, CN App Store) | ¥8 one-time | Realtime quotes in the status bar, **intraday chart**, price alerts, customizable gain/loss styling and refresh rate, drag to reorder; supports A-shares and funds | **Intraday chart only, no candlesticks**; no cost basis/P&L; no iOS app; utilitarian-feeling UI |
| **StockBar** (by Huizhou Jiqu, CN App Store) | ¥28 one-time | Menu bar prices for Shanghai/Shenzhen, HK, and US stocks and funds | Even simpler — quotes only |
| **Stock Ticker** (US App Store) | Free | Status bar carousel of NYSE/NASDAQ/forex/index quotes, several compact views | No charts, no A-shares, no P&L |
| **TickerBar** (open source, GitHub) | Free | Menu bar quotes + mini sparkline, price alerts, multiple exchanges | Developer-tool oriented; no candlesticks / P&L / multi-platform |
| **Market Bar** (open source, Swift) | Free | Minimalist realtime menu bar quotes | Same as above |
| **xbar / SwiftBar plugins** | Free | Scriptable menu bar tickers | Hacker-oriented, essentially no UI |

### 2. Heavyweight terminals (indirect competitors; they define our positioning by contrast)

Futu NiuNiu for Mac, THS/TongHuaShun for Mac, East Money: full-featured but heavy — slow to launch, screen-hogging, and visibly "opening a trading app" at work carries a psychological/social cost. **Pulse is positioned as their exact opposite: light, fast, discreet, absorbed at a glance.**

### 3. Built-in options

Apple's Stocks app + Notification Center widget: broad coverage and free, but not persistently in the menu bar, mediocre A-share experience, no cost basis/P&L, and shallow chart interactions.

### 4. iOS references (future form factor)

- **Ticker Island**: shows crypto/stock prices live in the Dynamic Island — proof that "prices in the Dynamic Island" is a real need, with paying users already.
- **Stocks+**: iPhone/Watch portfolio tracking — validates the widgets + position P&L combination.
- Apple's built-in Stocks widget: read-only, no P&L.

### Competitive takeaways

"Prices in the menu bar" is a crowded space (plenty of ¥8–¥28 utilities), but there are clear gaps:

1. **Nobody does candlesticks well in the glanceable context** — competitors offer at most an intraday line or a sparkline;
2. **Nobody does cost basis / P&L** — what watchers really care about is "am I up or down?";
3. **Nobody connects the Mac menu bar → widgets → Dynamic Island into one multi-platform glanceable suite**;
4. Chinese competitors' UIs generally feel "utilitarian" and lack modern design.

Pulse's differentiation = **candlestick trends + P&L perspective + multi-platform suite + design quality**.

---

## 2. Market Data Source Research

Requirements: US / HK / China A-share markets; realtime (or near-realtime) quotes + intraday + daily/weekly/monthly candles; affordable for an indie developer.

### Free options

| Source | Coverage | Capabilities | Risks |
|--------|----------|--------------|-------|
| **Yahoo Finance v8 chart API** (unofficial) | Global (A-shares `.SS`/`.SZ`, HK stocks `.HK`, US stocks) | Quotes + candles at any interval + pre/post-market, all in one endpoint; plus a symbol search endpoint | Unofficial; cookie/crumb auth churn and rate limits (tightened repeatedly in 2025); A-shares delayed 15 minutes |
| **Tencent quotes** `qt.gtimg.cn` (unofficial) | A-shares / HK / US | Realtime snapshot quotes (A-shares in realtime!), batch queries, extremely fast | Unofficial, no SLA, weak candle endpoints |
| **Sina quotes** `hq.sinajs.cn` (unofficial) | A-shares / HK / US / futures | Same as above; requires a Referer header | Same as above |
| **Longbridge OpenAPI** (official) | HK / US / CN / SG | Official realtime quotes + candles + **WebSocket push**, full SDKs (Swift via C/Rust bindings or REST) | Requires the user's own Longbridge account and API key (the author already has one); friction when distributing to others |

### Paid options (candidates for future commercialization)

- **AllTick / iTick**: specialize in US+HK+A-share realtime data, tick-level + candles, free tiers, designed for the China market
- **Polygon.io / Finnhub / Twelve Data**: strong on US stocks; weak or no A-share coverage
- **QOS.hk**: HK / US / A-share markets via REST + WebSocket

### Data source conclusion

**Abstract behind a protocol (`QuoteProvider`); never hard-wire any single vendor:**

- **MVP default**: Yahoo Finance (candles + search + US/HK stocks) + Tencent quotes (realtime A-share/HK snapshots to correct prices). Zero cost, no user configuration, works out of the box.
- **Optional upgrade**: a Longbridge OpenAPI provider — users enter their own key and get official realtime data and push (this is the author's own setup).
- **Commercialization stage**: if the app is ever sold, switch to licensed sources such as AllTick/iTick to avoid market data licensing risk (the biggest App Review and legal pitfall for quote apps — the interface is reserved for this in advance).

---

## 3. Platform Constraints Research (key findings)

These constraints directly shape the product design, so expectations are set up front:

1. **Menu bar (`MenuBarExtra`)**: native SwiftUI API on macOS 13+; the `.window` style can host arbitrarily complex views (a candlestick popover is no problem). Horizontal menu bar space is precious, so multiple symbols require the three display modes (carousel / compact / single symbol).
2. **macOS/iOS widgets (WidgetKit)**: the system refresh budget is roughly 40–70 updates per day — **second-level realtime is impossible**. Widgets are positioned as "low-frequency glances", showing "updated x minutes ago" to manage expectations.
3. **Dynamic Island (ActivityKit Live Activity)**: a single Activity lives at most 8 hours; high-frequency updates require APNs push or the `frequent-updates` entitlement. A good fit for "watching one stock during a trading session" (start at the open, end at the close), not for all-day persistence. Ticker Island has already validated this model.
4. **App Store review**: market data must come from licensed sources; free unofficial sources are fine for personal use, but a licensed source is required before commercial release.
