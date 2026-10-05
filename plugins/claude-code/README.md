# Pulse for Claude Code

Market quotes above your Claude Code prompt. Open `/pulse` to manage the
watchlist while you work. Use Yahoo Finance independently, or connect Pulse
Mac to display selected tickers from its watchlists through MCP.

![AAPL, NVDA, and MSFT prices above the Claude Code prompt](../../assets/readme/pulse-claude-code.png)

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
/pulse
```

The initial watchlist is empty. Add Yahoo ticker symbols, not company names.
Examples: `AAPL`, `BRK-B`, `0700.HK`, `600519.SS`, `7203.T`, `^GSPC`.
Hong Kong leading zeros are normalized; Shanghai `.SH` is accepted as an alias
for Yahoo's `.SS`. Yahoo's coverage determines which tickers can return a quote.
Unknown tickers stay visible with an error so you can correct or remove them.

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
| `/pulse source cc` | Use the independent Pulse CC watchlist |
| `/pulse source mac` | Read Pulse Mac watchlists and select tickers to display |
| `/pulse refresh` | Request one refresh round, including while paused |
| `/pulse off` | Pause automatic refresh; keep the watchlist and cached quotes |
| `/pulse on` | Resume automatic refresh |
| `/pulse help` | Show command usage |

The panel header switches between **Pulse CC** (Yahoo Finance) and **Pulse Mac**
(quotes from your Mac app), with Refresh and Pause beside them and a colored
status line below.

In Pulse CC mode, an add field sits above the watchlist. Each row shows the
ticker and its name, the price and change on the right, and a Remove button.
Rows carry no per-row clock; a quote from an earlier day, such as the last close
over a weekend, is labelled with its date so it never reads as today's. Narrow panes stack the price below the ticker. Add with Enter or
the field's submit button. Press `r` or `p` while the panel has focus; input
fields keep ordinary typing. Press Escape to return to the prompt.
The panel uses native controls on Claude Desktop and text controls in the
terminal; both draw the same layout. The footer links to
[pulseticker.app](https://www.pulseticker.app/).

In the terminal, a fullscreen session docks the panel beside the conversation:

![Pulse CC panel docked beside a Claude Code terminal session, with three tickers](../../assets/readme/pulse-cc-terminal-panel.png)

In Claude Desktop's **Code** tab, the panel opens beside the chat with native buttons:

<img src="../../assets/readme/pulse-cc-desktop-panel.png" width="480" alt="Pulse CC panel in Claude Desktop with the quote source buttons, an add field and two tickers">

## Connect Pulse Mac

Select **Pulse Mac** in `/pulse`. The first-connection card links to the
Mac download and takes the token. The local MCP
connection is included with the plugin; no `claude mcp add` command, server URL,
or port configuration is needed.

![Pulse CC first-connection card in the terminal, with the Mac download link and Paste token button](../../assets/readme/pulse-cc-mac-setup.png)

1. [Download Pulse Mac](https://www.pulseticker.app/) and open the app.
2. In Pulse Mac → **Settings → Agent access**, enable MCP and copy its token.
3. In `/pulse` → **Pulse Mac**, press **Paste token**. Paste into **Pulse Mac token**
   in Claude Code's configuration dialog, then save. Apply the reload if prompted
   and reopen `/pulse`.

Claude Desktop's local **Code** tab cannot show that dialog, so the card has a
token field instead: paste the token and press **Save**. Pulse passes it on
standard input to `claude plugin configure --values-stdin`, which saves it the
same way the dialog does. Start a new session to connect. The field shows the
token as you type.

<img src="../../assets/readme/pulse-cc-desktop-setup.png" width="360" alt="Pulse CC first-connection card in Claude Desktop with a token field and Save button">

The token is optional: leave it empty to keep using Yahoo Finance independently.
Claude Code saves the token in its secure credential store. The plugin never
saves the token in its watchlist store or sends it as command text or arguments.

Once connected, the checklist is replaced by your Mac watchlist groups. Press
**Show** beside a ticker to include it above the prompt; press **✓ Shown** to
hide it again. Use **Update token** when you rotate the token in Pulse Mac.

![Pulse CC panel connected to Pulse Mac through MCP, with watchlist groups and display selections](../../assets/readme/pulse-cc-mac-panel.png)

The same panel in Claude Desktop:

<img src="../../assets/readme/pulse-cc-desktop-mac-panel.png" width="480" alt="Pulse CC panel in Claude Desktop connected to Pulse Mac, with watchlist groups and Show buttons">

### If Claude Code blocks the reads

Claude Code checks the plugin's background reads against your permission
settings. In some modes, notably Claude Desktop's **Auto** mode, it refuses a
read that no message of yours asked for, even with a valid token. Pulse then
shows **Blocked by Claude Code permissions**, the refusal it received, and the
two read-only rules that allow it. Add them to `~/.claude/settings.json` (or
with `/permissions` in the terminal) and start a new session:

```json
{
  "permissions": {
    "allow": [
      "mcp__plugin_pulse-cc_pulse__list_watchlists",
      "mcp__plugin_pulse-cc_pulse__get_quotes"
    ]
  }
}
```

Merge them into an existing `allow` list. Writes, such as adding tickers or
recording trades in Pulse Mac, are not covered and still ask first.

The bundled connection appears in `/mcp` as `plugin:pulse-cc:pulse`. You can
inspect its status and tools or disable it there. The plugin configuration
contains only **Pulse Mac token**; refresh intervals and the local endpoint are
built in.

The plugin uses Claude Code's MCP connection and credentials. It calls only
`list_watchlists` and `get_quotes`. Showing or hiding a ticker never changes
Mac watchlists. Add/remove tickers and edit groups in Pulse Mac; their changes
appear at the next refresh. New tickers start unchecked. The same instrument
in multiple groups shares one selection and appears only once in the band.

The two sources are separate. **Pulse CC** retains your existing Yahoo
watchlist, including its saved order. **Pulse Mac** keeps a separate local
display selection, in the order selected. Switching sources neither imports
nor overwrites either list. Only the selected source appears above the prompt.
`/pulse add` and `/pulse remove` are available only in Pulse CC mode.

Mac mode requires Claude Code running locally on the same Mac as Pulse.
Keep Pulse open and Agent access enabled. Remote sessions cannot reach a
server on your Mac through their own `127.0.0.1`.

Mac quotes come from the app's **in-memory cache**. Refresh reads that cache;
it does not request a new quote from a provider. Each row retains the provider's
quote timestamp; an uncached instrument shows an unavailable message.
Mac mode reads lists and selected quotes every five seconds.
Pause stops automatic reads; Refresh performs one read while paused. Selecting
Pulse Mac also performs one initial read, so its groups are available while paused.

If the MCP connection fails, the panel retains the last list and the band marks
saved quotes **cached** and the source **Offline**. It retries every five seconds
without falling back to Yahoo. Select **Pulse CC** to return to
your independent list. A connection failure does not erase either selection.

The band shows up to five tickers in saved order, fitting fewer in a narrow
terminal. A `+N more` indicator points to the rest in `/pulse`. Gains are green,
losses red, and percentages always include their sign. USD is omitted in this
compact band; other currencies remain visible. The panel includes currency.
Neither surface displays charts or mini trends. Opening the panel does not
trigger an extra quote request.

Yahoo refresh waits 60 seconds **after each round**, with requests spaced at
least one second apart. A large watchlist takes longer to complete a round.

## Yahoo quote behavior

- Prices are Yahoo's **regular-session** quotes, not pre-market, after-hours,
  overnight quotes, or a live trade stream. The percentage compares the price
  with the previous close; when that is missing, it shows `—`.
- Each panel row shows Yahoo's quote timestamp in your local time. A closed
  market may correctly show the last trading session's price.
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

## Local data and privacy

The plugin saves Yahoo ticker symbols and the paused setting in Claude Code's
local plugin store (`watchlist.v1`). It separately saves the selected source and
Mac instrument references (`mac-view.v1`). It does not copy the MCP token into
plugin storage. That store is shared by your local sessions.
Edits in one session are picked up by another at its next refresh; concurrent
writes across processes are last-writer-wins. Quote caches are in memory and are
fetched again in a new session.

In Pulse CC mode, watching a ticker sends it to Yahoo Finance. In Mac mode,
only selected instrument references are sent to the configured Pulse MCP server;
the Mac app manages its provider connections. The plugin has no analytics,
account system, external backend, filesystem scanner, or model calls. It does
not add quotes or your watchlist to model prompts. A command's short reply, such
as `Added AAPL.`, is visible in the conversation. It never records trades.

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
decodes Yahoo responses, and `mac.ts` decodes Mac snapshots and quotes.
The implementation was written independently;
it does not include code from meme-watch.

## License

MIT. See [LICENSE](LICENSE).
