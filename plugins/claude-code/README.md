# Pulse for Claude Code

Market quotes above your Claude Code prompt. Open `/pulse` to manage the
watchlist of stocks, indices and crypto pairs while you work.

![AAPL, NVDA, BTC/USDT and ETH/USDT prices above the Claude Code prompt](https://raw.githubusercontent.com/fatwang2/Pulse/main/assets/readme/pulse-claude-code.png)

Requires **Claude Code 2.1.287 or later**, with Mods enabled. The ticker and
panel support the terminal and Claude Desktop's **Code** tab in local sessions.
Headless (`claude -p` / Agent SDK) sessions do not poll or draw a ticker;
Claude Desktop starts polling when its window attaches to the session.

## Install

```sh
claude plugin marketplace add fatwang2/Pulse
claude plugin install pulse-cc@pulse
```

Restart Claude Code or run `/reload-plugins`, then add tickers:

```text
/pulse add AAPL
/pulse add NVDA
/pulse add MSFT
/pulse add BTC/USDT
/pulse
```

The initial watchlist is empty. Add ticker symbols, not company names.
Examples: `AAPL`, `BRK-B`, `0700.HK`, `600519.SS`, `7203.T`, `^GSPC`.
Hong Kong leading zeros are normalized; Shanghai `.SH` is accepted as an alias
for `.SS`. The quote source's coverage determines which tickers return a quote.
Unknown tickers stay visible with an error so you can correct or remove them.

Add crypto as a pair written `BASE/QUOTE`: `BTC/USDT`,
`ETH/USDT`, `SOL/USDC`. Stocks and crypto share one list and one band. A symbol
with a dash, such as `BTC-USD`, is read as a ticker rather than a pair.

To update an installed plugin:

```sh
claude plugin marketplace update pulse
claude plugin update pulse-cc@pulse
```

Restart Claude Code or run `/reload-plugins` to apply the update.

## Use

| Command | Action |
| --- | --- |
| `/pulse` | Open or close the panel |
| `/pulse add <ticker>` | Add a ticker |
| `/pulse remove <ticker>` | Remove a ticker |
| `/pulse refresh` | Request one refresh round, including while paused |
| `/pulse off` | Pause automatic refresh; keep the watchlist and cached quotes |
| `/pulse on` | Resume automatic refresh |
| `/pulse help` | Show command usage |

The panel header shows the watchlist size with Refresh and Pause beside it and
a colored status line below. An add field sits above the watchlist. Each row shows the
ticker and its name, the price and change on the right, and a Remove button.
Rows carry no per-row clock; a quote from an earlier day, such as the last close
over a weekend, is labelled with its date so it never reads as today's. Narrow panes stack the price below the ticker. Add with Enter or
the field's submit button. Press `r` or `p` while the panel has focus; input
fields keep ordinary typing. Press Escape to return to the prompt.
The panel uses native controls on Claude Desktop and text controls in the
terminal; both draw the same layout. The footer links to
[pulseticker.app](https://www.pulseticker.app/).

In the terminal, a fullscreen session docks the panel beside the conversation:

![Pulse CC panel docked beside a Claude Code terminal session, with two stocks and two crypto pairs](https://raw.githubusercontent.com/fatwang2/Pulse/main/assets/readme/pulse-cc-terminal-panel.png)

In Claude Desktop's **Code** tab, the band sits above the prompt and the panel
opens beside the chat with native buttons:

![Claude Desktop with Pulse CC prices above the prompt and the panel beside the chat](https://raw.githubusercontent.com/fatwang2/Pulse/main/assets/readme/pulse-cc-desktop.png)

The band shows up to five tickers in saved order, fitting fewer in a narrow
terminal. A `+N more` indicator points to the rest in `/pulse`. Gains are green,
losses red, and percentages always include their sign. USD is omitted in this
compact band; other currencies remain visible. The panel includes currency.
Neither surface displays charts or mini trends. Opening the panel does not
trigger an extra quote request.

Pulse CC refreshes 60 seconds **after each round**. Stock requests are spaced
at least one second apart, so a large watchlist takes longer to complete a
round; crypto pairs are read together in one request.

## Stock quote behavior

Stock and index quotes come from Yahoo Finance.

- Prices are Yahoo's **regular-session** quotes, not pre-market, after-hours,
  overnight quotes, or a live trade stream. The percentage compares the price
  with the previous close; when that is missing, it shows `—`.
- A quote from an earlier day is labelled with its date. A closed market may
  correctly show the last trading session's price.
- Exchange delays vary. Delay is shown when Yahoo supplies it; missing delay
  metadata is never presented as proof of real-time data. See
  [Yahoo's exchange data guide](https://help.yahoo.com/kb/finance/article-exchanges-data-delays-sln2310.html).
- Network or provider failures keep the last successful price and label it
  **Cached**. An unavailable ticker with no cached quote shows an error.
- HTTP 429 pauses the remaining round. Retries respect `Retry-After` (at least
  60 seconds) and repeated throttling backs off. Manual refresh respects this
  cooldown too.

Yahoo's chart endpoint is unofficial, has no availability guarantee, and may
change or be unavailable in some regions. Software's MIT license does not grant
rights to Yahoo's market data. These quotes are for informational use.

## Crypto quote behavior

- Pairs are read from Binance's public Spot market-data API
  (`data-api.binance.vision`). No API key or account.
- One request reads every pair, in batches of 100, on the same 60-second
  refresh as stocks. Crypto trades around the clock, so the percentage is the
  **24-hour** change: the last price against the price 24 hours earlier.
- Binance Spot data is not delayed. The band omits the quote currency because
  the pair already names it; the panel shows it.
- An unknown or delisted pair shows its own error without stopping the other
  pairs. A Yahoo rate limit never delays crypto refreshes.

## Local data and privacy

The plugin saves Yahoo ticker symbols, Binance pairs and the paused setting in
Claude Code's local plugin store (`watchlist.v1`). That store is shared by your
local sessions. Edits in one session are picked up by another at its next
refresh; concurrent writes across processes are last-writer-wins. Quote caches
are in memory and are fetched again in a new session.

Watching a ticker sends it to Yahoo Finance and watching a pair sends it to
Binance. The plugin has no analytics, account system, external backend,
filesystem scanner, or model calls. It does not add quotes or your watchlist to
model prompts. A command's short reply, such as `Added AAPL.`, is visible in the
conversation. See the [Pulse privacy policy](https://www.pulseticker.app/privacy#pulse-cc).

Versions before 0.4.0 could also display Pulse Mac watchlists through a bundled
MCP connection. 0.4.0 removes that mode, the connection and its token option;
a session that had Pulse Mac selected shows your own watchlist, which was kept
separately all along. The old display setting (`mac-view.v1`) is left unread.

## What the mod runs

Pulse CC is a Claude Code mod: functions in `hooks/register.tsx` that Claude
Code calls in its own process. Everything it does goes through the mods API,
and every host call is written out in that one file.

- **Hooks and what they do:** `session.start` registers `/pulse` and, in a
  terminal session, starts the quote refresh. `session.attach` and
  `session.detach` start and stop the refresh when Claude Desktop connects or
  disconnects. `session.end` stops it. `command.run` answers `/pulse` and no
  other command. `ui.render` draws the band above the prompt and the `/pulse`
  panel. It has no hook on Claude's tool calls, prompts, permission checks or
  messages, so it never sees, changes or approves them.
- **What it fetches and sends, and where:** HTTPS `GET` requests to exactly two
  fixed addresses, each written whole at its call:
  `https://query1.finance.yahoo.com/v8/finance/chart/<symbol>` for stocks and
  indices, and `https://data-api.binance.vision/api/v3/ticker/24hr?symbols=<pairs>`
  for crypto pairs. A request carries only the watched symbols, a
  `Pulse-CC/<version>` user agent and `Accept: application/json`; no token,
  cookie, account or other data. They run about once a minute while prices are
  shown, plus manual refreshes. It contacts no other hosts, and responses are
  read only as quote data: nothing in them is run or treated as a command.
- **Tools, commands and programs:** none. It calls no MCP or other tools, runs
  no slash commands, starts no processes and runs no shell commands.
- **Local data:** its plugin store holds the watchlist and paused setting
  described above. It has no configuration options and reads no environment
  variables, files or credentials. The panel's link to
  `https://www.pulseticker.app/` opens in your browser and sends nothing.

## Development and verification

From the Pulse repository root, load a local checkout for one session:

```sh
claude --plugin-dir ./plugins/claude-code
```

This works before the marketplace is published and does not install the plugin.
To install from a local checkout instead:

```sh
claude plugin marketplace add .
claude plugin install pulse-cc@pulse
```

Keep that checkout in place for updates. GitHub installation uses the published
marketplace and plugin files on the repository's default branch.

Run the native checks:

```sh
claude plugin validate plugins/claude-code
claude plugin validate .
claude plugin test plugins/claude-code
```

Run these commands from the repository root. Tests use Claude Code's native
Mods harness: mocked host network, local store and clock, plus terminal and
Desktop drawing/input checks. They make no model calls or live requests.

The plugin ID is `pulse-cc`; the display title and command are `Pulse` and `/pulse`.

For type checking, first load this plugin with `--plugin-dir` so Claude Code
generates your installed version's declarations in `.claude-plugin/types/`, then:

```sh
npm exec --yes --package=typescript@5.9.3 -- tsc -p plugins/claude-code
```

Generated declarations stay local and are ignored by Git. All host API calls
live in `hooks/register.tsx`; `watchlist.ts` manages lifecycle, `yahoo.ts`
and `binance.ts` decode stock and crypto quotes.
The implementation was written independently;
it does not include code from meme-watch.

## License

MIT. See [LICENSE](LICENSE).
