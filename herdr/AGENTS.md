# Pulse for Herdr

- `pulse/` is the mod folder shared at herdr.dev/mods: keep it to `mods/pulse/`,
  `RECIPE.md` and `preview.png`. `pulse-layout/` is the "Herdr + Pulse" layout
  shared at herdr.dev/layouts: `layouts/herdr-pulse.json` (with its settings
  picture), an identical copy of `mods/pulse/`, `RECIPE.md` and `preview.png`.
  Change the mod in `pulse/mods/pulse/` and copy it over; a test checks the
  copies match. Tests and docs stay outside both.
- Follow Herdr's installed `AGENTS.md`, `herdr.d.ts` and `gpui-kit.d.ts`.
  Mods are plain JavaScript in QuickJS: no Node APIs, no `setTimeout`, no
  `Intl`. Never keep a `cx` past its callback; the refresh loop owns the one
  from its `cx.spawn`.
- Keep `quotes.js` and `watchlist.js` free of Herdr imports so
  `node --test herdr/tests/*.test.mjs` can run them.
- The only hosts are `query1.finance.yahoo.com` and `data-api.binance.vision`.
  The only program is `open` with `PULSE_URL`, and only on a click on a Pulse
  link. No `hc` or file access. Keep README, RECIPEs and code in step on
  hosts, programs, storage and behavior.
- Promote Pulse for Mac only; name no other edition.
- Respect Yahoo cooldowns; never show cached data as fresh or unknown delay
  as real time. Crypto never waits on Yahoo.
- Update the RECIPEs with every behavior change; each `preview.png` must be a
  screenshot of the real mod or layout running in Herdr.
