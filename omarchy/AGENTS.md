# Repository working agreements

## Colors

- Use colors from the active Omarchy system theme. Do not hard-code UI colors.
- Pass semantic colors down from `Panel.qml` as **required** component
  properties, so a theme change propagates through every view and a component
  cannot quietly fall back to a literal.
- `ThemePalette.rise` and `ThemePalette.fall` carry market direction. They read
  the theme's own ANSI green and red, because the shell's `Color` singleton
  exposes red as `urgent` but has no green role at all.
- Everything else derives from `Color.foreground`, `Color.background`,
  `Color.accent` or `Color.urgent`, with muted, hover and selected variants
  produced by alpha on an inherited color — never by a second hex value.
- `ThemePalette.qml` is the one file allowed to contain a hex pattern, and only
  because it is parsing the theme's `colors.toml`, not painting with it.
- `tests/test_panel_source.sh` enforces this. Keep it updated rather than
  working around it.

## Color is never the only indicator

A rise and a fall must be separable without seeing color:

- percentages always carry their sign (`+0.94%`, `-2.17%`),
- a flat row takes the neutral foreground rather than the rise color,
- feed state shows a labelled `LIVE` / `LOADING` / `OFFLINE`, not just a dot.

## The data layer is a port, not a rewrite

`Market.js`, `SymbolID.js` and `YahooAdapter.js` are ports of PulseCore's
`Market.swift`, `SymbolID.swift` and `YahooProvider.swift` in the historical
Mac source (`fatwang2/Pulse`, tag `v0.15.8`). That reference is no longer
in this checkout; preserve it through the historical tag. When the two
disagree, the Swift version is the reference implementation — it is the one
that has been in front of users. Port the behavior, including the reasons in
its comments; do not improve it in passing and do not drop a case because the
plugin does not reach it yet.

The one deliberate divergence is symbol validation. Pulse gets every symbol
from a provider's search index, so it never needs to check one. Here the
watchlist is a file a person edits by hand, so `SymbolID.create` refuses a code
that cannot resolve rather than creating a row that can never quote.

## JavaScript modules

QML resources declare dependencies with `.import "X.js" as X`, which must be
the first statements in the file. That is not valid JavaScript, so the Node
tests load these files through `tests/qmljs.js`, which rewrites `.import` into
`require`. Keep that shim literal: if it starts interpreting, the tests stop
testing what the shell runs.

Every module ends with a `typeof module !== "undefined"` export guard so the
same file works in both places.

## Requests

Yahoo rate-limits hard per IP and answers one symbol per request. Requests are
serialised through a queue with a one-second spacing, and a closed market is
not polled at all. Do not add a parallel fan-out, a shorter floor than the
15-second clamp in `Watchlist.qml`, or a refresh on a timer faster than the
source can actually change.

## Ordering is the user's

Display order is the schedule's; the persisted order is the user's. The
rows normally show `SessionOrder.orderedSymbols` — market blocks led by the
session trading now, pins atop their own block — and the saved sequence is
only the tiebreak inside a block. The one rule that keeps this honest: any
control that edits the sequence must only ever be shown against the raw
sequence. That is what the reordering pass is — it bypasses the schedule so
the arrows edit the order the eye sees. Never surface a move control against
the schedule view. Membership and order are list operations and live in edit mode's row
controls and the tab strip; the quote detail describes one instrument and
holds no list controls.

## Interactions are the shell's, functions are the app's

When porting a macOS interaction, keep what it does and re-express how.
List editing is a mode, entered from the header's pencil: rows grow move,
pin and remove controls at their right edge, the tabs disable, and the
schedule order is bypassed so the arrows edit the sequence the eye sees.
Nothing is revealed on hover — hover-revealed controls were tried twice
(beside the chart, then over the price) and rejected both times; reading
the list and editing the list are different postures, entered deliberately.
QQC.Popup context menus were also tried and render poorly against the
shell's panels. Inline text fields for naming and a double click to edit a
label in place are the shell idioms that stayed.

If a grouped presentation is ever wanted, it must be a presentation of an
unchanged order, and the move buttons must disappear with it.

## Settings live in the file

`~/.config/omarchy/pulse/watchlist.json` is the source of truth. The settings
view is an editor for it, not a second store, and every mutation writes the
whole file through `Watchlist.save()`.

Two rules that are easy to break there:

- Unknown keys are carried through a write untouched. A newer Pulse's settings
  must survive being edited by an older one, and silently dropping them is the
  one failure a user cannot see.
- Nothing writes before the first successful read. Otherwise a transient parse
  failure or a missing file gets persisted as an empty watchlist.

Omarchy's `barWidget.schema` is registered into `BarWidgetRegistry` and read by
nothing in 4.0.0 — `metadataFor` has no callers. Do not add a declarative
settings form expecting it to render; it will not.

## Tests

`make test` runs the JavaScript reducers and the source checks; `make validate`
adds `qmllint` and `omarchy plugin validate`. `qmllint` cannot resolve `qs.Ui`
or `qs.Commons` outside the quickshell runtime, so those import warnings are
expected — the reference Omarchy plugins produce them too. The real runtime
check is installing the plugin and calling `omarchy-shell pulse.omarchy status`.
