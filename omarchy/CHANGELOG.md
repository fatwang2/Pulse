# Changelog

## v0.1.1 — 2026-08-25

The marketplace review's finding, the regression fixing it caused, and the
housekeeping around both.

### Fixed
- Every dynamic `Text` binding renders as `Text.PlainText`. QML's default
  `AutoText` sniffs a bound string for rich-text markup, so a crafted name in
  a Yahoo response could parse as markup and initiate resource loads inside
  the long-lived shell process — the finding HANCORE-linux raised on the
  marketplace submission. The name tooltip moves to a `PlainToolTip` clone of
  the shell's own component for the same reason, and `tests/test_plaintext.js`
  fails the build on the next label added without it.
- The panel header says "Pulse" again. That pass inserted its lines
  mechanically after each `text:` anchor, and one anchor was the first line of
  a multiline ternary, so the panel opened under the title "true".

### Changed
- The panel header's mark wears `Color.accent`, the way the macOS popover
  draws its waveform in the system accent color. The bar icon stays
  foreground, mirroring the template menu-bar icon it corresponds to.
- The `textFormat` lines sit at their block's indentation rather than at
  column zero, where the same mechanical pass left them.
- README: a fresh install starts empty, removal is documented, and the panel
  has a preview image.

## v0.1.0 — 2026-08-21

First release: the MVP loop — install, watch, add, organize, inspect — is
complete and verified on a live Omarchy 4 desktop.

### Watchlists
- Named lists as tabs: "+" creates one with an inline name field, a double
  click renames in place, hover reveals delete; `1`–`9` switch.
- One config file, `~/.config/omarchy/pulse/watchlist.json`, edited from the
  panel or any text editor — both sides land live, unknown keys survive a
  write, and a v1 file migrates to the versioned shape on first read.
- Edit mode from the header's pencil (or `e`): reorder, pin and remove at
  each row's edge, against your saved order.

### Display
- Schedule-aware ordering, ported from the macOS app: markets group into
  blocks and the session trading now leads — Asia through the Beijing day,
  the US after 17:00 — with pins atop their own market block. A settings
  toggle turns it off.
- Rows carry the session's intraday line beside the price; it rides in the
  quote response, costing no extra request.
- Extended sessions marked (`PRE` / `POST`), measured against the regular
  close; `STALE` appears only while a market is open, past the source's own
  delay — a closed market's last print is the close, never stale.
- Theme-native: every color derives from the active Omarchy theme, with
  market rise/fall read from the theme's own palette.

### Search
- A full page, as on macOS: the magnifier swaps the watchlist for it, tabs
  stay live above, adding keeps the page open, and a new symbol joins at
  the top of its own market block.
- Recent searches persist as chips (last eight); a typed code that names
  its venue (`600519.SH`, `7203.T`) resolves locally even where Yahoo's
  index cannot.

### Quote detail
- The session line at reading size plus daily / weekly / monthly
  candlesticks with a volume strip, cached ten minutes per symbol and
  period; OHLC, amplitude, volume, currency — and provenance: which source,
  what delay, as of when.

### Bar
- Three forms: icon (default), a pinned quote, or a carousel rotating
  through every priced row, colored by direction.

### Data
- Yahoo Finance, one request per second, closed markets not polled, every
  request carrying a deadline so a hung connection becomes a failed row
  rather than a stuck panel. US real time; HK/CN ~15 min; JP/KR ~20 min;
  COMEX/NYMEX metals ~10 min.
- The symbol layer already models crypto pairs, spot metals, Korean boards
  and vendor index spellings, so the multi-provider layer the macOS app
  routes across (Binance, Tencent, Sina, Naver, Longbridge) can arrive
  without changing what a symbol is.

### Known limits
- One data source: crypto and spot metals parse but cannot price yet, and
  Chinese/Japanese/Korean name search awaits the native-language providers.
- No position tracking yet.
