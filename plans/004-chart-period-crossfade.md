# 004 — Crossfade chart period switches and de-flash the spinner

- **Status**: APPLIED (build verified; feel-check pending)
- **Commit**: c215d71
- **Severity**: MEDIUM
- **Category**: Missed opportunity (preventing jarring change) / Purpose & frequency
- **Estimated scope**: 1 file (`PulseMac/Sources/DetailView.swift`), ~20 lines

## Problem

Switching the period control (分时 / 日K / 周K / 月K) hard-swaps the chart:

```swift
// PulseMac/Sources/DetailView.swift:31-38 — current
.task(id: period) {
    isLoading = true
    defer { isLoading = false }
    candles = await appState.engine.loadCandles(
        for: symbol, period: period,
        count: candleCount(for: period)
    )
}
```

```swift
// PulseMac/Sources/DetailView.swift:227-252 — current
@ViewBuilder
private var chart: some View {
    ZStack {
        if candles.isEmpty {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                ContentUnavailableView { ... }
            }
        } else if period.isIntraday {
            IntradayChartView(...)
        } else {
            CandlestickChartView(...)
        }
    }
    ...
}
```

Two seams:

1. When new candles arrive, the old chart (or spinner) is replaced in a single
   frame — an abrupt full-region repaint right where the user is looking.
2. On a fast load (cached/local), `isLoading` flips true→false within ~100ms,
   flashing the `ProgressView` for a frame or two on first open. A spinner that
   flashes reads as jank; one that appears only when loading is actually slow
   reads as responsiveness.

## Target

Candle arrival is wrapped in an animated transaction so the branch change
cross-fades (~180ms ease-out — entrances get ease-out; stay well under 300ms
since users flick between periods repeatedly). The spinner only appears after
150ms of real waiting.

```swift
// target — task block
.task(id: period) {
    // Show the spinner only when loading is actually slow: a sub-150ms load
    // (cache hit) swaps silently instead of flashing a progress indicator.
    let spinnerDelay = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        isLoading = true
    }
    defer {
        spinnerDelay.cancel()
        isLoading = false
    }
    let loaded = await appState.engine.loadCandles(
        for: symbol, period: period,
        count: candleCount(for: period)
    )
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
        candles = loaded
    }
}
```

```swift
// target — chart branches get explicit opacity transitions
private var chart: some View {
    ZStack {
        if candles.isEmpty {
            if isLoading {
                ProgressView().controlSize(.small)
                    .transition(.opacity)
            } else {
                ContentUnavailableView { ... }   // unchanged content
                    .transition(.opacity)
            }
        } else if period.isIntraday {
            IntradayChartView(...)               // unchanged args
                .transition(.opacity)
        } else {
            CandlestickChartView(...)            // unchanged args
                .transition(.opacity)
        }
    }
    .animation(.easeOut(duration: 0.18), value: candles.isEmpty)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

With `reduceMotion` from `@Environment(\.accessibilityReduceMotion)`.
(A cross-fade is already the reduced-motion-safe form of this transition, but
`withAnimation(nil)` keeps the swap instant for users who asked for less —
opacity-only transitions are gentle either way; keep the branch anyway for
consistency with plans 001/002.)

Note the old chart stays visible while the next period loads (candles isn't
cleared on `period` change) — that behavior is good, keep it; the crossfade
happens only at the moment of data arrival.

## Repo conventions to follow

- If plan 001 was executed first, `DetailView` already has the `reduceMotion`
  environment property — reuse it, don't redeclare.
- `withAnimation` wrapping a state mutation is the established pattern:
  `WatchlistView.swift:270-272` (share feedback) is the exemplar.

## Steps

1. `PulseMac/Sources/DetailView.swift` — ensure
   `@Environment(\.accessibilityReduceMotion) private var reduceMotion` exists
   on `DetailView` (add if plan 001 hasn't landed).
2. Replace the `.task(id: period)` block (lines ~31-38) with the target
   version.
3. In `private var chart` (lines ~227-252), append `.transition(.opacity)` to
   each of the four branches and add
   `.animation(.easeOut(duration: 0.18), value: candles.isEmpty)` to the
   `ZStack`, keeping all existing content and arguments untouched.

## Boundaries

- Do NOT modify `IntradayChartView` / `CandlestickChartView` internals
  (`Packages/PulseUI`) — no data-point interpolation; the crosshair's 1:1
  un-animated hover tracking is correct direct manipulation, leave it alone.
- Do NOT animate the segmented picker itself — it's a system control.
- Do NOT cache or restructure candle loading beyond the spinner-delay task.

## Verification

- **Mechanical**: app scheme builds with zero new warnings.
- **Feel check**:
  - Open a symbol's detail, flick through 分时 → 日K → 周K → 月K quickly:
    each arrival cross-fades in ~180ms; the old chart never blinks to a spinner
    if data returns fast; spamming the picker never strands a stale spinner.
  - On a slow network (Network Link Conditioner or first uncached load), the
    spinner appears only after a beat, fading in rather than popping.
  - Hover the chart during a period switch: crosshair still tracks 1:1 with no
    added lag.
- **Done when**: no hard cut is visible anywhere in the chart region and quick
  loads show no spinner flash.
