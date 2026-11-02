# Pulse for opencode

- An opencode TUI plugin (npm package `opencode-pulse-ticker`, entry
  `exports["./tui"]` = `src/tui.tsx`). opencode compiles the TSX with its own
  Solid runtime, so ship source, no build step and no runtime dependencies.
  Use only `@opencode-ai/plugin/tui` APIs that exist since opencode 1.15
  (`slots`, `keymap.registerLayer`, `kv`, `lifecycle`, `ui`), and test in a real
  opencode before release.
- `src/quotes.js` and `src/watchlist.js` are copies of the Herdr mod's
  (`herdr/pulse/mods/pulse/`): only the header comment and `PULSE_URLS` differ,
  and a test checks it. Change both copies together. Keep them and
  `src/format.js` free of opencode imports so `node --test` can run them.
- The only hosts are `query1.finance.yahoo.com` and `data-api.binance.vision`.
  The only program is the system's browser on a `PULSE_URLS` link, and only on
  a click. Keep README and code in step on hosts, programs, storage and behavior.
- Promote Pulse for Mac only, modestly (the sidebar link, the detail's last
  line, the README); name no other edition. Links carry `utm_source=opencode`.
- Respect Yahoo cooldowns; never show cached data as fresh or unknown delay as
  real time. Crypto never waits on Yahoo.
- `preview.png` must be a screenshot of the real plugin running in opencode.
