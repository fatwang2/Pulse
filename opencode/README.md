# Pulse for opencode

An [opencode](https://opencode.ai) plugin from the makers of
[Pulse for Mac](https://www.pulseticker.app/?utm_source=opencode&utm_medium=readme): a stock and
crypto watchlist in the session sidebar, and a one-line quote band along the
bottom of the window. Each ticker in the sidebar shows its price, today's line and its change; click one for its day: the open, high, low and previous
close, and whether its market is open. Stocks and indices come from Yahoo
Finance, crypto pairs (`BTC/USDT`) from Binance's public Spot data.

![Pulse in the opencode sidebar](preview.png)

## Install

Requires opencode 1.15 or later. Add the plugin to `tui.json`
(`~/.config/opencode/tui.json` for every project, or `.opencode/tui.json` in one):

```json
{
  "$schema": "https://opencode.ai/tui.json",
  "plugin": ["opencode-pulse-ticker"]
}
```

Restart opencode and open a session: Pulse appears in the sidebar. To start
from your own list instead of the starter one (AAPL, NVDA, ^GSPC, BTC/USDT),
pass it as an option:

```json
{
  "plugin": [["opencode-pulse-ticker", { "symbols": ["AAPL", "0700.HK", "^GSPC", "BTC/USDT"], "placement": "bottom" }]]
}
```

`placement` sets where the quote band goes; `/pulse-band` changes it later:

| `placement` | Where |
| --- | --- |
| `bottom` (default) | The bottom line of the window, on every screen |
| `right` | Right of the model name inside the prompt, first two tickers |
| `off` | No band; the sidebar only |

## Use

| Command | What it does |
| --- | --- |
| `/pulse-add` | Add a ticker: `AAPL`, `0700.HK`, `600519.SS`, `^GSPC`, `BTC-USD` (Yahoo) or a Binance Spot pair such as `BTC/USDT` |
| `/pulse-remove` | Pick a ticker to remove |
| `/pulse-refresh` | Refresh now |
| `/pulse-pause` | Pause or resume automatic refresh |
| `/pulse-band` | Move the quote band, or turn it off |

The same commands are in the command palette (`ctrl+p`) under Pulse. Click a
row for its detail, and the "Pulse" heading to fold the panel.

Quotes refresh every minute. Stock requests are spaced a second apart, and
when Yahoo rate limits them, Pulse waits (one minute, doubling up to fifteen)
before it asks again; crypto pairs keep refreshing meanwhile. A quote from an
earlier day carries its date, and a delay Yahoo does not state is shown as
"delay unknown", never as real time.

## Privacy

Pulse sends read-only requests to two hosts, `query1.finance.yahoo.com` and
`data-api.binance.vision`, with the tickers on your list and nothing else. Your
watchlist stays in opencode's own state on your computer. The only program the
plugin starts is your system's browser (`open`, `xdg-open` or `start`), and
only when you click "Pulse for Mac".

Market data belongs to its providers and is for information only, not
investment advice.

## Pulse for Mac

Want the same watchlist in your menu bar, with charts and positions?
[Pulse for Mac](https://www.pulseticker.app/?utm_source=opencode&utm_medium=readme)

## Development

Point `tui.json` at your checkout and restart opencode after each change:

```json
{ "plugin": ["/path/to/Pulse/opencode"] }
```

`node --test opencode/tests/*.test.mjs` from the repository root runs the tests.
`src/quotes.js` and `src/watchlist.js` are shared with the Herdr mod; see
[AGENTS.md](AGENTS.md).

MIT licensed. See [LICENSE](LICENSE).
