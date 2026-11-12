# Pulse for Rex

- A Node CLI (npm package `rex-pulse-ticker`, bin `pulse-rex`) plus
  `lua/pulse.lua`, which Rex's `init.lua` loads. Rex lets config draw no UI, so
  the watchlist is a terminal program in a pane; the Lua only registers
  `rex.action`s and runs `pulse-rex`. No runtime dependencies.
- `src/quotes.js` and `src/watchlist.js` are copies of the Herdr mod's
  (`herdr/pulse/mods/pulse/`): only the header comment and `PULSE_URLS` differ,
  and a test checks it. Change all copies together. Keep them, `src/format.js`
  and `src/store.js` free of Rex calls so `node --test` can run them.
- `src/format.js` is pure: state in, lines out. Every line must fit its pane
  width (a test draws many sizes); measure with `cells`, cut with `fit`.
- `pulse-rex install` only adds or replaces the block between
  `-- >>> pulse >>>` and `-- <<< pulse <<<` in Rex's `init.lua`, runs
  `rex config check`, and restores the file when the check fails. Never touch
  the rest of the file, and never rewrite it on start or on use.
- Pane width: Rex sizes splits by fraction and the app evens out a new split
  after it shows, so `pulse_open` passes `--beside` and `--ratio` and the pane
  calls `session.resize_pane` itself after it starts.
- The only hosts are `query1.finance.yahoo.com` and `data-api.binance.vision`.
  The only program is `rex` (layers, resizing, config check and reload). Pulse
  for Mac links are OSC 8 hyperlinks; Pulse never opens a browser itself. Keep
  README and code in step on hosts, programs, storage and behavior.
- Promote Pulse for Mac only, modestly (the footer link, the detail's card,
  the README); name no other edition. Links carry `utm_source=rex`.
- Respect Yahoo cooldowns; never show cached data as fresh or unknown delay as
  real time. Crypto never waits on Yahoo.
- Test in a real Rex before release: `rex config check` on an `init.lua` that
  loads the Lua, `rex do <that file> --action pulse_open`, and a look at the
  pane, the layer and the band.
- Releases: bump `version` in `package.json` (the User-Agent reads it), merge
  to main, then push the tag `rex-v<version>`. `.github/workflows/release-rex.yml`
  checks the tag, tests, publishes `rex-pulse-ticker` to npm with provenance
  through npm trusted publishing (repository `fatwang2/Pulse`, workflow
  `release-rex.yml`, environment `npm`; no token is stored) and creates a
  GitHub release. A version npm already has is skipped.
- `pulse-rex install` writes node and the package through a version manager's
  stable link when there is one (`…/node/current/bin/node`), so upgrading node
  doesn't break Rex's config.
