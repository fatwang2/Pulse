# Pulse for Herdr

- `pulse/` is the folder shared at herdr.dev/mods: keep it to `mods/pulse/`,
  `RECIPE.md` and `preview.png`. Tests and docs stay outside it.
- Follow Herdr's installed `AGENTS.md`, `herdr.d.ts` and `gpui-kit.d.ts`.
  Mods are plain JavaScript in QuickJS: no Node APIs, no `setTimeout`, no
  `Intl`. Never keep a `cx` past its callback; the refresh loop owns the one
  from its `cx.spawn`.
- Keep `quotes.js` and `watchlist.js` free of Herdr imports so
  `node --test herdr/tests` can run them.
- The only hosts are `query1.finance.yahoo.com` and `data-api.binance.vision`.
  No `exec`, `hc` or file access. Keep README, RECIPE and code in step on
  hosts, storage and behavior.
- Respect Yahoo cooldowns; never show cached data as fresh or unknown delay
  as real time. Crypto never waits on Yahoo.
- Update `RECIPE.md` with every behavior change; `preview.png` must be a
  screenshot of the real mod running in Herdr.
