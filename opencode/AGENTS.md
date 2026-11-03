# Pulse for opencode

- An opencode TUI plugin (npm package `opencode-pulse-ticker`, entry
  `exports["./tui"]` = `src/tui.tsx`) for both opencode lines. opencode compiles
  the TSX with its own Solid runtime, so ship source, no build step and no
  runtime dependencies. `src/tui.tsx` exports `{ id, tui, setup }`: v1
  (`opencode-ai` 1.15+) calls `tui` (`src/v1.tsx`: `@opencode-ai/plugin/tui`
  `slots`, `keymap.registerLayer`, `kv`, `lifecycle`, `ui`), v2 (`@opencode/cli`
  2.x) calls `setup` (`src/v2.tsx`: `@opencode/plugin/tui` `ui.slot`,
  `keymap.layer`, `storage.store`, promise dialogs). Both render the views in
  `src/view.tsx`. v2's `storage.store` updates only after its file is written,
  so `v2.tsx` keeps an unsaved edit in memory until then. Test both lines in a
  real opencode before release.
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
- The quote band shows quotes only, never a Pulse for Mac link, and uses only
  slots opencode adds content to (v1 `app_bottom`, `*_prompt_right`; v2 `append`
  to `app`, `prompt.footer`, `sidebar.content`). Never replace opencode's own UI
  (v1 `session_prompt`, `home_prompt`, `home_logo`; v2 `replace` claims).
- `preview.png` must be a screenshot of the real plugin running in opencode.
- Releases: bump `version` in `package.json` and `VERSION` in `src/view.tsx`
  together (a test checks they match), merge to main, then push the tag
  `opencode-v<version>`. `.github/workflows/release-opencode.yml` checks the tag,
  tests, publishes to npm with provenance through npm trusted publishing
  (repository `fatwang2/Pulse`, workflow `release-opencode.yml`, environment
  `npm`; no token is stored) and creates a GitHub release. A version npm
  already has is skipped.
