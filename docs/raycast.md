# Pulse for Raycast

- A Raycast Store extension with one command, Search Symbol. Keep it a lookup
  tool: no menu-bar command and no watchlist, so it does not duplicate Pulse
  for Mac. Watchlists over the Mac app's local MCP are a later version.
- Search reuses Pulse's published catalog (`symbols-v1.json`, built by
  pulse-server) and the Mac app's ranking (exact, then prefix, then substring;
  popularity inside a tier). Never build a separate index or call a search API.
- The only hosts are `www.pulseticker.app` (the catalog),
  `query1.finance.yahoo.com` and `data-api.binance.vision`. Quote logic is
  ported from `herdr/pulse/mods/pulse/quotes.js`; keep their behavior in step.
- Download the catalog at most once a day, conditionally (ETag), and refuse a
  file far smaller than the one in hand.
- Respect Yahoo cooldowns; never show cached data as fresh or an unknown delay
  as real time.
- Promote Pulse for Mac only, with `utm_source=raycast`; name no other edition.
- Follow Raycast's Store rules: US English UI, Title Case action titles,
  `CHANGELOG.md` with `{PR_MERGE_DATE}`, `package-lock.json` committed,
  `npm run lint` and `npm run build` clean before publishing.
- Keep tests and other dev material out of `raycast/`: the Store reviewer
  asked for only the extension, `README.md`, `CHANGELOG.md`, `media/` and
  `metadata/`. Tests live in `tests/raycast/` and run with `npx tsx`.
- Publish only from the owner's Mac mini (see Releasing). Never from CI or a
  fresh machine, and never store a GitHub token.

## Development

```sh
npm install
npm run dev      # opens the extension in Raycast
make -C .. test-raycast   # tests (in tests/raycast/, outside the Store folder), lint, build, typecheck
npm run lint
```

## Releasing

The Raycast Store takes extensions as pull requests to `raycast/extensions`,
and `ray publish` opens or updates that pull request. It keeps its own clone
of the fork in `~/.config/raycast/public-extensions-fork` and updates the open
submission only from the machine holding that clone. A fresh machine (or a CI
runner) rebuilds the `ext/pulse` branch, which closes the open submission and
opens a new one. So publish from the Mac mini only:

```sh
cd raycast
GIT_CONFIG_COUNT=2 \
  GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=fatwang2 \
  GIT_CONFIG_KEY_1=user.email GIT_CONFIG_VALUE_1=fatwang2@users.noreply.github.com \
  GITHUB_ACCESS_TOKEN="$(gh auth token)" npx ray publish
```

The token is gh's existing sign-in and is used for this command only.
