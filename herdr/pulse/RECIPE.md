# Pulse

A stock and crypto watchlist docked beside your agents. Add tickers such as `AAPL`, `0700.HK` or `BTC/USDT`; prices and signed daily changes refresh every 60 seconds. Dock it as a short strip at the top or bottom and it becomes a one-line quote band.

![Pulse](preview.png)

## What you see

A panel docked on the right, 300px wide, in the theme's `chrome` background with `foreground` text at 12.5px. Top to bottom:

- **Header**, 12px padding: `PULSE · 3 TICKERS` (11px, semibold, `muted`, truncates) with two small outlined buttons on the right, **Refresh** and **Pause** (22px high, 8px horizontal padding, radius 5, `border` outline, 11px `muted` text; hover fills `hover`). Pause reads **Resume** while paused.
- **Status line** under it: a 6px round dot and 11.5px text in one color. `Auto-refresh every 60s` in `done`, `Refreshing quotes…` in `working` (the dot pulses with a native opacity loop, 0.35 to 1 over 1.2s), `Auto-refresh paused` in `blocked`.
- **Add field**, 10px below: a 30px input, radius 6, `background` fill, `input` border (`accent` while focused), placeholder `Add a ticker: AAPL, 0700.HK, BTC/USDT`. Under it, one short line when there is something to say: an error in `ansi1`, the last edit's notice (`Added AAPL.`) in `dim`, or a Yahoo rate-limit note in `blocked`.
- **Watchlist**, the rest of the height, scrolling. One row per ticker in saved order, 12px by 7px padding, `hover` background on hover:
  - left: the ticker (semibold, truncates) and under it in 11px `dim` the instrument name, `As of Oct 31` when the quote is from an earlier local day, and `Delay 15m` when Yahoo reports a delay, joined with ` · `;
  - right-aligned: the price with its currency (`230.10 USD`, `65,000.00 USDT`, `0.00000441`) and under it the signed change (`+1.23%`) in `ansi2` for gains, `ansi1` for losses, `dim` when unknown (`—`);
  - far right: a `dim` `×` that removes the ticker.
  - A failed refresh adds an 11px `blocked` line: `Cached quote · <reason>` when an older price is kept, the reason alone when there is none. Before the first quote, the price reads `Waiting…` (`Not fetched` while paused).
  - Empty: `Your watchlist is empty. Add a ticker above.` in `dim`.
- **Footer**, a `border` line above, 10.5px `dim`: the sources (`Yahoo Finance · Regular-session quotes · Exchange delays vary · pulseticker.app`, or the crypto variant naming Binance Spot and 24h change when a pair is watched).

**Band**: when the block is under 72px tall (docked top or bottom), the same mod draws one row instead: `Pulse` in `dim` semibold, `Paused` in `blocked` if paused, then each ticker as `AAPL 230.10 +1.23%` (symbol semibold, price without USD or the pair's own quote currency, change colored as above, `cached` in `dim` after a failed refresh), 14px apart, clipped at the right edge. With nothing watched it says `Make the panel taller to add tickers.`

## How it behaves

- Agent status plays no part: the panel looks the same whatever agents are doing.
- **Adding**: Enter in the field adds the ticker. Input is upper-cased and checked: Yahoo symbols (`AAPL`, `BRK-B`, `^GSPC`, `7203.T`) or Binance pairs written `BASE/QUOTE`. `700.HK` becomes `0700.HK`; `600519.SH` becomes `600519.SS`. Company names and anything URL-like are refused with an inline error. A duplicate says it is already there. The field clears on success.
- **Removing**: `×` removes the ticker and its cached quote at once.
- **Refreshing**: a round starts right after any edit, then 60 seconds after the previous round ends. Pairs go first, up to 100 per Binance request. Stocks go one at a time to Yahoo, at least one second apart. A pair Binance doesn't know fails only itself: a failed batch is retried pair by pair.
- **Rate limits**: a Yahoo 429 stops the round, marks the remaining stocks `Refresh deferred`, and holds stock requests for at least 60 seconds, doubling on repeats up to 15 minutes. Crypto keeps refreshing through the cooldown. Refresh respects the cooldown for stocks.
- **Pause / Resume**: automatic rounds stop and start; Refresh still runs one round while paused. Cached quotes stay.
- **Commands**: `pulse.refresh` and `pulse.pause` (toggle) reach shown copies through `nextCommand()`; bind them in `keys.json` if wanted. No keys are bound by default.
- Nothing moves except the status dot while refreshing.

## Built from

- **One mod**, `mods/pulse/`, no layout. `mod.json`: `{ "place": "right", "size": 300, "title": "Pulse" }`, so the first time Herdr sees it, it docks on the right.
- `main.js`: the view (`gpui-kit` `div`, `gpui-base` `h_flex`, `v_flex`, `InputState` + `Input`), sized with `on_size_change` to pick panel or band. Colors only from `theme()`.
- `watchlist.js`: the list and the refresh loop, with no Herdr imports. Herdr's APIs are passed in as a host: `load`/`save`, `fetch`, `now`, `sleep`, `changed`. The loop runs in one `cx.spawn` for the copy's whole life, sleeping with that task's `cx.sleep` and redrawing with its `cx.notify()`. Edits are synchronous; each bumps a revision so a round in flight drops late results, and wakes the loop.
- `quotes.js`: symbol rules, the two URLs, decoding, and number and date formatting by hand (no `Intl` in Herdr's runtime).
- **Storage**: `shared("pulse.watchlist.v1")` / `setShared(...)`, persisted by Herdr and seen by every copy: `{ version: 1, symbols: [...], paused }`. The loop re-reads it each round. Quotes are memory only.
- **Network**: `fetch` GETs, with headers `User-Agent: Pulse-Herdr/<version>` and `Accept: application/json`, to two hosts only:
  - `https://query1.finance.yahoo.com/v8/finance/chart/<symbol>?interval=1d&range=1d&includePrePost=false`: `chart.result[0].meta`, using `regularMarketPrice`, `regularMarketTime`, `previousClose` (else `chartPreviousClose`), `currency`, `longName`/`shortName`, `exchangeDataDelayedBy`. A response whose `meta.symbol` differs from the request is rejected.
  - `https://data-api.binance.vision/api/v3/ticker/24hr?symbols=["BTCUSDT",...]`: `lastPrice`, `prevClosePrice`, `closeTime`.
- Herdr functions: `theme`, `shared`, `setShared`, `nextCommand`. No `exec`, no `hc`, no files outside the mod.

## Watch out

- The mod reaches the network (Yahoo Finance and Binance, nothing else) and runs no programs.
- Herdr's `fetch` response has no headers, so Yahoo's `Retry-After` can't be read; the 60-second floor stands in for it.
- Yahoo's chart endpoint is unofficial and may be unavailable in some regions. Prices are regular-session, not pre- or after-hours. Never label cached data as fresh or unknown delay as real time.
- Each shown copy runs its own refresh loop, and timers keep running while a copy is hidden. One copy is the intended setup; a second copy doubles the requests.
- `toLocaleString` options are ignored in Herdr's QuickJS: format prices with grouping and 2 decimals (2 to 4 significant digits below 1) by hand.
- Keep the change colors on `ansi2`/`ansi1`; a theme's own `done` color isn't necessarily green.
- `pulseticker.app` in the footer is plain text, not a link (opening a browser would mean running a program).

## Done when

- `herdr-app check mods/pulse` passes.
- `node --test` on the Pulse repository's `herdr/tests` passes (symbol rules, decoding, formatting, the refresh loop with a fake clock).
- Adding `AAPL`, `0700.HK` and `BTC/USDT` shows three rows with prices within a few seconds; `Apple` shows an error and adds nothing.
- `×` removes a row immediately; Pause stops automatic requests and Refresh still runs one round.
- Resizing the block below 72px shows the one-line band; taller shows the panel again.
- Restarting Herdr keeps the watchlist and paused state.
