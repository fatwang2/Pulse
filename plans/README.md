# Animation Improvement Plans

Written by the `improve-animations` audit at commit `c215d71` (2026-07-11).
Each plan is self-contained: any agent can execute it without audit context.
Run one plan per session/diff and feel-check before moving on
(`improve-animations execute <plan>` or hand the file to any agent).

| # | Plan | Severity | Status |
| --- | --- | --- | --- |
| 001 | [Make price ticks actually animate](001-animate-price-ticks.md) | HIGH | APPLIED |
| 002 | [Animate popover navigation and height changes](002-popover-navigation-continuity.md) | HIGH | APPLIED |
| 003 | [Add press feedback to custom plain buttons](003-press-feedback-buttons.md) | MEDIUM | APPLIED |
| 004 | [Crossfade chart period switches, de-flash spinner](004-chart-period-crossfade.md) | MEDIUM | APPLIED |

All four applied at commit `c215d71` working tree (2026-07-11); build verified
(`xcodegen generate` + Debug build, zero new warnings). Human feel-check
pending — the checklist lives in each plan's Verification section.

## Recommended execution order

1. **001** — highest product impact, smallest diff; also introduces the
   `accessibilityReduceMotion` environment pattern the later plans reuse.
2. **002** — biggest feel change; needs a careful feel-check of the
   `MenuBarExtra(.window)` resize behavior (fallback documented in the plan).
3. **003** — independent of the others; safe anytime.
4. **004** — touches `DetailView` like 001 does; run after 001 to avoid
   conflicting edits in the same file.

## Dependencies

- 004 reuses the `reduceMotion` property added by 001 (it adds it itself if
  001 hasn't landed, but expect a trivial merge overlap if run in parallel).
- 001+004 both edit `DetailView.swift`; 001+002+003 all edit
  `WatchlistView.swift` in disjoint regions. Sequential execution avoids all
  conflicts.

## Audited but not planned (LOW / optional)

- ~~Watchlist ↔ search-results hard cut~~ — DONE (2026-07-11): 150ms ease-out
  cross-fade on the empty ↔ non-empty boundary; typing stays instant.
- Website hover motion not gated for touch; reduced-motion still applies
  hover transforms instantly (`website/app/globals.css`) — REVERTED
  (2026-07-11): a fix was applied and then rolled back by owner decision; the
  website is out of scope for now (no auto-deploy). The finding itself stands:
  wrap the four hover transform/animation rules (`.brand:hover`,
  `.cta-primary/.cta-secondary:hover`, `.product-shot:hover`,
  `.preview-row:hover`) in `@media (hover: hover) and (pointer: fine)` and add
  `transform: none` for them under `prefers-reduced-motion` — batch with the
  next website change.
- ~~Empty-state entrance (delight budget)~~ — DONE (2026-07-11): staggered
  fade-up (icon, then text at +60ms), offset dropped under reduced motion.
- Instant hover-highlight flips on rows and icon buttons — deliberately kept:
  native macOS hover highlights are instant; hover fires tens of times a day
  (frequency rule: reduce, don't embellish).
- Menu-bar rotation / in-app sparkline draw-in — deliberately NOT animated:
  both are seen 100+ times a day (frequency rule: no animation).
- Search debounce is 800ms (`WatchlistView.swift`, `.task(id: searchText)`) —
  a latency issue, not motion. 300–400ms is typical; lowering it roughly
  doubles worst-case search API calls (rate-limit tradeoff). Product decision,
  intentionally left unchanged.
