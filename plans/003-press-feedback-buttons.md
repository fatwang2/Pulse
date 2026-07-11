# 003 — Add press feedback to custom plain buttons

- **Status**: APPLIED (build verified; also applied to the search-field clear button, which the plan's list had missed)
- **Commit**: c215d71
- **Severity**: MEDIUM
- **Category**: Physicality & origin (press feedback)
- **Estimated scope**: 1 new file + 2 edited files, ~40 lines

## Problem

Every custom control in the popover uses `.buttonStyle(.plain)` with a custom
label, which on macOS renders **no pressed state at all**. Hover feedback
exists (background tint via `onHover`), but the press itself is mute — the
interface doesn't confirm it heard the click until the action's effect lands.

Affected pressables (all verified current):

```swift
// PulseMac/Sources/WatchlistView.swift:196-209 — refresh button (footer)
Button { appState.engine.poke() } label: { ... }
.buttonStyle(.plain)
.onHover { refreshHovering = $0 }
```

```swift
// PulseMac/Sources/WatchlistView.swift:604-617 — IconButton (back chevron, etc.)
Button(action: action) { ... }
.buttonStyle(.plain)
```

```swift
// PulseMac/Sources/WatchlistView.swift:663-677 — ClusterIcon (briefcase toggle)
Button(action: action) { ... }
.buttonStyle(.plain)
```

```swift
// PulseMac/Sources/WatchlistView.swift:709-714 — SearchResultRow add (+) button
Button(action: onAdd) { ... }
.buttonStyle(.plain)
```

```swift
// PulseMac/Sources/DetailView.swift:302-307 — "add position" inline button
Button(PulseLocalization.localizedString("action.addPosition")) { ... }
.buttonStyle(.plain)
```

## Target

One shared `ButtonStyle` giving subtle scale-down + dim on press, applied to
the five call sites above. Scale stays in the 0.95–0.98 band; response is
ease-out and ≤160ms.

```swift
// new file: PulseMac/Sources/PressableButtonStyle.swift
import SwiftUI

/// Press feedback for custom-label buttons: `.plain` on macOS shows nothing on
/// press, so pressables using it confirm the click with a subtle scale + dim.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { .init() }
}
```

Each affected call site changes exactly one line:

```swift
// target — at every location listed above
.buttonStyle(.pressable)   // was: .buttonStyle(.plain)
```

Why these values: press feedback budget is 100–160ms with ease-out (fast start
= instant acknowledgment); scale 0.96 is within the recommended 0.95–0.98 so it
reads as tactile, not cartoonish. Feedback appears on press-down (SwiftUI's
`isPressed` flips on mouse-down), which is the Apple "respond on pointer-down"
rule. Under reduced motion the scale is dropped but the opacity dim (a
non-vestibular cue) remains.

## Repo conventions to follow

- New shared view utilities live as single-purpose files in
  `PulseMac/Sources/` (exemplar: `WatchRowColumnLayout.swift`).
- Comments in English (repo convention).
- `ButtonStyle`'s `makeBody` replaces the default styling entirely, so the
  existing custom hover backgrounds inside the labels are unaffected.

## Steps

1. Create `PulseMac/Sources/PressableButtonStyle.swift` with the code above.
   Add the file to the PulseMac target the same way existing sources are
   registered (check `project.yml` / the Xcode project — mirror however
   `WatchRowColumnLayout.swift` is included).
2. `WatchlistView.swift:208` (refresh button): `.plain` → `.pressable`.
3. `WatchlistView.swift:614` (IconButton): `.plain` → `.pressable`.
4. `WatchlistView.swift:674` (ClusterIcon): `.plain` → `.pressable`.
5. `WatchlistView.swift:714` (SearchResultRow add): `.plain` → `.pressable`.
6. `DetailView.swift:305` ("add position"): `.plain` → `.pressable`.

## Boundaries

- Do NOT restyle `ClusterMenu` (`WatchlistView.swift:621-652`) — it is a
  `Menu`, not a `Button`; the system owns its press behavior.
- Do NOT touch the reorder "Done" button (`WatchlistView.swift:41-48`) — it
  uses `.glassProminent`, which already provides system press feedback.
- Do NOT touch `WatchRow` — rows use `TapGesture`, not `Button`; row press
  states are out of scope here.
- Do NOT change hover behavior or any layout.

## Verification

- **Mechanical**: app scheme builds; the new file is a member of the PulseMac
  target (build fails loudly if not registered).
- **Feel check**:
  - Mouse-down (and hold) on the refresh arrow: it shrinks to 0.96 and dims
    immediately on down, springs back on release.
  - Same on back chevron, briefcase icon, search "+", and "add position".
  - The scale must feel like a tap acknowledgment, not a bounce — if it reads
    springy, the duration drifted; keep 140ms ease-out.
  - Reduce Motion ON: press still dims (opacity 0.8) but no scaling.
- **Done when**: every custom pressable visibly acknowledges mouse-down.
