# 002 — Animate popover navigation and height changes

- **Status**: APPLIED (build verified; feel-check pending — watch the window-resize/slide interplay)

> **Follow-up (perf, 2026-07-11)**: the initial implementation stuttered on some
> pushes. Two fixes applied on top of this plan:
> 1. Each route view is now pinned to its own target height inside
>    `ZStack(alignment: .top)`, so the animated container height only clips and
>    composites per frame instead of relayouting both live view trees.
> 2. `DetailView` holds its first candle render (`isFirstLoad`, 350ms clearance
>    from task start) so Swift Charts' expensive initial render — up to 1440
>    intraday points — no longer lands mid-slide on cache hits.
- **Commit**: c215d71
- **Severity**: HIGH
- **Category**: Missed opportunity (spatial consistency) / Purpose & frequency
- **Estimated scope**: 2 files (`PulseMac/Sources/PopoverRootView.swift`, `PulseMac/Sources/WatchlistView.swift`), ~30 lines

## Problem

Navigation is the most frequent interaction in the popover after hovering, and
today it teleports twice at once:

1. **Route swaps are hard cuts.** `PopoverRootView` switches the entire content
   with no transition:

```swift
// PulseMac/Sources/PopoverRootView.swift:35-66 — current
var body: some View {
    Group {
        switch route {
        case .list:
            WatchlistView(route: $route)
        case .detail(let symbol):
            DetailView(symbol: symbol, route: $route)
        case .position(let symbol, let returnRoute):
            ...
        case .settings:
            SettingsView(route: $route)
        }
    }
    .frame(width: 340, height: height)
}
```

2. **The window height jumps.** The same frame snaps between per-route heights
   (list ≈ 220–600, detail 560, position 360, settings 540 —
   `PopoverRootView.swift:70-83`), so opening a detail page makes the window
   pop to a new size with zero continuity.

There is also a smaller cut of the same family: deleting a watchlist row is an
unanimated mutation, so the row vanishes and the list reflows abruptly:

```swift
// PulseMac/Sources/WatchlistView.swift:453-455 — current
Button(PulseLocalization.localizedString("action.delete"), role: .destructive) {
    appState.watchlist.remove(item.symbol)
}
```

Spatial model: the list is the root; detail, position editor, and settings are
children (each has a back/cancel affordance returning to list). A push/pop
transition makes that hierarchy legible; today nothing explains where a screen
came from.

## Target

One animated transaction drives both the content swap and the frame height, and
children push from the trailing edge / pop back to it (spatial consistency:
exit the way you entered). Under reduced motion, the slide is dropped and only
a short cross-fade remains.

```swift
// target — PopoverRootView.swift body
@Environment(\.accessibilityReduceMotion) private var reduceMotion

private var pushTransition: AnyTransition {
    reduceMotion
        ? .opacity
        : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
}

private var rootTransition: AnyTransition {
    reduceMotion
        ? .opacity
        : .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
}

var body: some View {
    ZStack {
        switch route {
        case .list:
            WatchlistView(route: $route)
                .transition(rootTransition)
        case .detail(let symbol):
            DetailView(symbol: symbol, route: $route)
                .transition(pushTransition)
        case .position(let symbol, let returnRoute):
            // (existing if-let body unchanged)
            ...
                .transition(pushTransition)
        case .settings:
            SettingsView(route: $route)
                .transition(pushTransition)
        }
    }
    .frame(width: 340, height: height)
    .clipped()
    .animation(.snappy(duration: 0.28), value: route)
    .animation(.snappy(duration: 0.28), value: height)
}
```

Notes on the target:

- `Group` becomes `ZStack` so the outgoing and incoming views can overlap
  during the transition instead of stacking vertically.
- `.clipped()` keeps the sliding view from painting outside the popover while
  the window resizes.
- The children always live "to the right": pushing list→detail slides the
  detail in from trailing while the list exits leading; popping reverses both.
  This is exactly the asymmetric pair above — no direction bookkeeping needed.
- `.animation(_, value: route)` requires `PopoverRoute: Hashable` — it already
  is (`PopoverRootView.swift:4`). The second `.animation(_, value: height)`
  covers height changes that happen *without* a route change (rows
  added/removed while on the list).
- Duration 0.28 `.snappy`: inside the modal/drawer budget (200–500ms) but close
  to the dropdown band, because this fires tens of times a day.

Row deletion joins the same motion language:

```swift
// target — WatchlistView.swift:453-455
Button(PulseLocalization.localizedString("action.delete"), role: .destructive) {
    withAnimation(.snappy(duration: 0.22)) {
        appState.watchlist.remove(item.symbol)
    }
}
```

## Repo conventions to follow

- `.snappy(duration:)` is the house spring — see
  `WatchlistView.swift:42,270,475`. Do not introduce other curves.
- Transition style exemplar already in-repo: the share-feedback HUD combines
  `.opacity` with a second effect (`WatchlistView.swift:132`); the reorder
  handle uses `.move(edge: .trailing).combined(with: .opacity)`
  (`WatchlistView.swift:825`). The push transition intentionally reuses that
  exact combination.

## Steps

1. `PulseMac/Sources/PopoverRootView.swift` — add
   `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to
   `PopoverRootView`.
2. Same file — add the two computed `AnyTransition` properties from the target.
3. Same file — change `Group {` to `ZStack {` in `body`, attach the transitions
   per case as shown (the `.position` case attaches to the `if let` content —
   wrap the existing `if let` in a `Group` and put `.transition(pushTransition)`
   on that `Group` so both branches transition), and append `.clipped()` plus
   the two `.animation` modifiers after `.frame(...)`.
4. `PulseMac/Sources/WatchlistView.swift:453-455` — wrap the delete mutation in
   `withAnimation(.snappy(duration: 0.22))` as shown.

## Boundaries

- Do NOT change the height formula (`PopoverRootView.swift:70-83`) or the
  340pt width.
- Do NOT animate the popover's own open/close — that belongs to
  `MenuBarExtra(.window)` / the system.
- Do NOT add a navigation library or restructure routing; `PopoverRoute` stays.
- If the body structure has drifted from the excerpt, STOP and report.

## Verification

- **Mechanical**: app scheme builds with zero new warnings.
- **Feel check** (this plan MUST be feel-checked; window-resize animation under
  `MenuBarExtra(.window)` can stutter on some macOS versions):
  - Click a row: detail slides in from the right while the list slides out
    left, and the window height grows smoothly in the same beat — one motion,
    not two.
  - Press back: exact mirror (detail exits right, list returns from left).
  - Open Settings and Position editor: same push/pop behavior.
  - Delete a row via context menu: remaining rows slide up; the window height
    (if on the list route) follows without a snap.
  - Spam back/forward quickly: transitions retarget mid-flight (springs are
    interruptible) — no queueing, no flash of empty content.
  - **If the NSWindow resize visibly fights the content slide** (tearing or
    stepped resize), fall back to animating only `value: route` with the slide
    and letting height change un-animated — report which variant shipped.
  - Reduce Motion ON: pure cross-fade, no sliding, height still animates.
- **Done when**: no navigation in the popover produces a hard cut, and rapid
  navigation never glitches.
