# Pulse for Herdr

A [Herdr](https://herdr.dev) mod: a stock and crypto watchlist docked beside
your agents. Stocks and indices come from Yahoo Finance, crypto pairs
(`BTC/USDT`) from Binance's public Spot data. Docked as a short strip, it
draws a one-line quote band instead.

The shareable folder is [`pulse/`](pulse/): `mods/pulse/`, the
[`RECIPE.md`](pulse/RECIPE.md) another agent can build it from, and
`preview.png`.

## Install

Ask the agent running in Herdr:

```text
Read ~/.config/herdr-app/AGENTS.md, then add this mod: https://github.com/fatwang2/Pulse/tree/main/herdr/pulse
```

Or copy `pulse/mods/pulse/` to `~/.config/herdr-app/mods/pulse/` and run
`herdr-app check ~/.config/herdr-app/mods/pulse`. It docks on the right the
first time Herdr sees it.

## Use

- Type a ticker in the field and press Enter: `AAPL`, `0700.HK`, `^GSPC`,
  `BTC/USDT`. `×` removes one.
- **Refresh** runs a round now; **Pause** stops automatic rounds.
- `pulse.refresh` and `pulse.pause` can be bound in `keys.json`.

Quotes refresh 60 seconds after each round. Stock prices are Yahoo's
regular-session quotes; exchange delays vary and are shown when Yahoo reports
them. Crypto changes are 24-hour. A quote from an earlier day carries its date.

## Privacy

The watchlist is saved in Herdr's own shared state on your computer. Watching
a ticker sends it to Yahoo Finance; watching a pair sends it to Binance. The
mod contacts no other host, runs no programs, reads no files and has no
account or analytics. See the [Pulse privacy policy](https://www.pulseticker.app/privacy).

## Development

```sh
node --test herdr/tests
```

The tests cover symbol rules, decoding, formatting and the refresh loop
with a fake clock. Rendering needs Herdr itself: `herdr-app check`.
