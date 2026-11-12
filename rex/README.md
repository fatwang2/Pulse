# Pulse for Rex

A stock and crypto watchlist in a [Rex](https://www.superlogical.com/rex) pane
beside your agents, from the makers of
[Pulse for Mac](https://www.pulseticker.app/?utm_source=rex&utm_medium=readme).
Each ticker shows its price and its change. The selected ticker's day fills
the rest of the pane: a chart, the open, high, low and
previous close, and where the numbers come from. Press Enter for the same day
in a floating layer. Stocks and indices come from Yahoo Finance, crypto pairs
(`BTC/USDT`) from Binance's public Spot data. Squeezed to six rows or fewer,
the pane draws a one-line quote band instead.

## Install

Needs Node.js 18.17 or later and Rex's `rex` command on your `PATH`.

```sh
npm install --global rex-pulse-ticker
pulse-rex install
```

`pulse-rex install` adds one marked block to the end of Rex's `init.lua`
(`~/.config/rex/init.lua`, or where `REX_CONFIG` points), checks it with
`rex config check`, and reloads Rex's config. If the check fails, the file is
put back as it was. `pulse-rex uninstall` removes the block.

Then press **cmd+shift+p** in Rex and type **Pulse**:

| Action | Name | What it does |
| --- | --- | --- |
| Pulse: Open Watchlist | `pulse_open` | Opens the watchlist about 48 columns wide beside the focused pane, or focuses the one already open in this window |
| Pulse: Add Ticker… | `pulse_add` | A small prompt for a ticker; `rex do pulse_add symbol=0700.HK` adds one directly |
| Pulse: Refresh Quotes | `pulse_refresh` | One round now in every open Pulse pane |
| Pulse: Pause or Resume | `pulse_pause` | Stops automatic refresh, or starts it again |

No keys are bound by default. To bind one, add a line after the Pulse block in
`init.lua`, such as `rex.bind("cmd+shift+u", "pulse_open")`, or pass `keys` to
`setup`: `keys = { open = "cmd+shift+u" }`. `width = 56` makes the pane wider.

Without the palette, `pulse-rex` runs the watchlist in any terminal.

## Use

- It starts with `AAPL`, `NVDA`, `^GSPC` and `BTC/USDT`.
- `↑` `↓` (or `j` `k`, or the mouse wheel) select a ticker; a click selects
  one, a second click opens it.
- `Enter` opens the selected ticker's day in a floating layer; `Esc` closes it.
- `a` adds a ticker: `AAPL`, `0700.HK`, `^GSPC`, `BTC/USDT`. `x` removes the
  selected one.
- `r` refreshes now; `p` pauses or resumes automatic refresh; `q` closes the pane.
- From a shell: `pulse-rex add NVDA`, `pulse-rex remove NVDA`,
  `pulse-rex pause`, `pulse-rex resume`, `pulse-rex refresh`, `pulse-rex list`.
  Open panes pick changes up within a second.

Quotes refresh 60 seconds after each round. Stock prices are Yahoo's
regular-session quotes; exchange delays vary and are shown when Yahoo reports
them. Crypto changes and lines are 24-hour. A quote from an earlier day
carries its date. Early in a session, today's line only reaches as far as the
day has gone.

Want quotes in your menu bar, with charts and positions? That's
[Pulse for Mac](https://www.pulseticker.app/?utm_source=rex&utm_medium=readme).

## Privacy

The watchlist is saved in `~/.config/pulse-rex/watchlist.json` (or under
`XDG_CONFIG_HOME`). Watching a ticker sends it to Yahoo Finance; watching a
pair sends it to Binance. Pulse contacts no other host and has no account or
analytics. The Pulse for Mac links are terminal hyperlinks to
`https://www.pulseticker.app/`, tagged `utm_source=rex&utm_medium=plugin`;
your terminal opens them only when you click one. The only program Pulse runs
is `rex`, to open its layers and set its pane's width. See the
[Pulse privacy policy](https://www.pulseticker.app/privacy).

## How it fits into Rex

Rex has no plugin UI of its own, so Pulse is a terminal program in a pane, and
`lua/pulse.lua` is the glue Rex's config loads: four `rex.action`s that open
the pane with `rex.session.new_split` and change the saved list by running
`pulse-rex`. The pane sizes itself with `session.resize_pane` once Rex shows
it, and opens the detail with `session.new_layer`.

## Development

```sh
node --test rex/tests/*.test.mjs
```

The tests cover drawing (every line fits its pane at every size, the chart,
the band, wide characters), keys, the shared watchlist file, the `init.lua`
block, and that `quotes.js` and `watchlist.js` match the Herdr mod's. The
Lua needs Rex itself: write an `init.lua` that `dofile`s `rex/lua/pulse.lua`
and run `rex config check` on it.
