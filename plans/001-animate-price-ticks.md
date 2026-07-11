# 001 — Make price ticks actually animate (dead contentTransition)

- **Status**: APPLIED (build verified; feel-check pending)
- **Commit**: c215d71
- **Severity**: HIGH
- **Category**: Purpose & frequency / Missed opportunity (state indication)
- **Estimated scope**: 2 files (`PulseMac/Sources/WatchlistView.swift`, `PulseMac/Sources/DetailView.swift`), ~10 lines

## Problem

Pulse is a stock ticker. The single most important moment of motion in the whole
product — a price changing — currently does not animate at all, even though the
code *intends* it to.

Three Text views carry `.contentTransition(.numericText())`:

```swift
// PulseMac/Sources/WatchlistView.swift:801-806 — current (row price)
Text(priceText)
    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
    .lineLimit(1)
    .minimumScaleFactor(0.75)
    .allowsTightening(true)
    .contentTransition(.numericText())
```

```swift
// PulseMac/Sources/WatchlistView.swift:853-860 — current (row metric)
Text(display.text)
    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
    .foregroundStyle(display.color)
    .lineLimit(1)
    .minimumScaleFactor(0.65)
    .allowsTightening(true)
    .contentTransition(.numericText())
```

```swift
// PulseMac/Sources/DetailView.swift:104-107 — current (hero price)
Text(PriceFormatter.price(quote.price))
    .font(.system(size: 28, weight: .semibold).monospacedDigit())
    .foregroundStyle(color)
    .contentTransition(.numericText())
```

Two defects:

1. **The transition never fires.** `contentTransition` only takes effect when the
   text change happens inside an animated transaction. Quote updates flow from
   `RefreshEngine` → `MarketStore` (plain `@Observable` mutation, no
   `withAnimation` anywhere in `Packages/PulseCore` or on these views — verified
   by grep). So every price update is a hard swap; the modifier is dead code.
2. **No direction.** `.numericText()` without `value:` rolls digits in a fixed
   direction. With `value:` the digits roll **up when the number increases and
   down when it decreases** — exactly the semantics a ticker wants.

## Target

Each of the three Texts animates its own content change, scoped to that view
(do NOT wrap the store mutation — that would animate unrelated layout):

```swift
// target — row price (WatchlistView.swift)
Text(priceText)
    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
    .lineLimit(1)
    .minimumScaleFactor(0.75)
    .allowsTightening(true)
    .contentTransition(reduceMotion ? .opacity : .numericText(value: quote?.price ?? 0))
    .animation(.snappy(duration: 0.25), value: priceText)
```

```swift
// target — row metric (WatchlistView.swift)
Text(display.text)
    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
    .foregroundStyle(display.color)
    .lineLimit(1)
    .minimumScaleFactor(0.65)
    .allowsTightening(true)
    .contentTransition(reduceMotion ? .opacity : .numericText())
    .animation(.snappy(duration: 0.25), value: display.text)
```

(The metric column mixes percent/P&L formats whose numeric value isn't a single
Double, so it keeps the value-less form; direction matters most on the price.)

```swift
// target — hero price (DetailView.swift)
Text(PriceFormatter.price(quote.price))
    .font(.system(size: 28, weight: .semibold).monospacedDigit())
    .foregroundStyle(color)
    .contentTransition(reduceMotion ? .opacity : .numericText(value: quote.price))
    .animation(.snappy(duration: 0.25), value: quote.price)
```

Where `reduceMotion` is `@Environment(\.accessibilityReduceMotion)` — under
reduced motion the digits cross-fade instead of rolling (feedback kept, movement
dropped).

Values: animation `.snappy(duration: 0.25)` — matches the repo's existing
`withAnimation(.snappy(duration: 0.2/0.25))` convention in
`WatchlistView.swift:270,475`. Stay under 300ms: refresh ticks arrive every few
seconds while the popover is open; the roll must read as a flick, not a show.

## Repo conventions to follow

- Animation vocabulary: this repo exclusively uses `.snappy(duration:)` springs
  (`WatchlistView.swift:42,270,276,471,475,507`). Do not introduce
  `easeInOut`/custom curves here.
- Environment access pattern: `@Environment(AppState.self) private var appState`
  at the top of the struct — add `@Environment(\.accessibilityReduceMotion)
  private var reduceMotion` alongside it in `WatchRow` and `DetailView`.

## Steps

1. `PulseMac/Sources/WatchlistView.swift` — in `struct WatchRow` (line ~742),
   add `@Environment(\.accessibilityReduceMotion) private var reduceMotion`
   next to the existing `@Environment(AppState.self)`.
2. Same file, line ~806: replace `.contentTransition(.numericText())` on the
   price Text with the target block above (contentTransition + `.animation`).
   `quote` is already in scope (declared at line ~752).
3. Same file, line ~860 (`rowMetricView(display:)`): apply the metric target
   block. Note this helper is nested in `WatchRow`, so `reduceMotion` is in
   scope. Also delete the stray duplicate `.lineLimit(1)` on line ~861.
4. `PulseMac/Sources/DetailView.swift` — add the same `@Environment`
   property to `DetailView` (line ~6-12 area), then apply the hero target
   block at line ~107. `quote` is non-nil inside this `if let quote` branch.

## Boundaries

- Do NOT touch `Packages/PulseCore` — no `withAnimation` in the data layer.
- Do NOT add animation to `menuBarText` (NSStatusItem label — not animatable).
- Do NOT animate the change/percent line in the hero (DetailView.swift:116-122)
  or the stats grid — price and row metric only.
- If line numbers have drifted, locate by the code excerpts; if the excerpts
  don't exist anymore, STOP and report.

## Verification

- **Mechanical**: `swift build --package-path Packages/PulseCore` passes; then
  build the app scheme in Xcode (or `xcodebuild -scheme PulseMac build`) with
  zero new warnings.
- **Feel check**: run the app with a live symbol (crypto ticks fastest — add
  BTC-USD), open the popover, and confirm:
  - digits roll (per-digit slide) when the price refreshes, upward roll on an
    uptick, downward on a downtick;
  - the row layout does not shift while digits roll (monospacedDigit holds);
  - tapping the metric column (cycles 涨跌幅 → 今日盈亏 → 持仓盈亏) rolls the
    metric text;
  - with System Settings → Accessibility → Display → Reduce motion ON, the
    change is a plain cross-fade, no rolling.
- **Done when**: every price refresh visibly animates in list rows and the
  detail hero, and reduce-motion falls back to opacity.
