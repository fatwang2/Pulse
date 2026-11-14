import type { Quote } from './yahoo'
import { formatChange } from './yahoo'

/** The scene name Pulse sets with `$.theme.set` and answers at `Backdrop`. */
export const SCENE = 'pulse-mood'
export const BACKDROP_KEY = 'backdrop.v1'
export type BackdropPreference = { version: 1; enabled: boolean }

export function readBackdrop(value: unknown): BackdropPreference {
  const saved = value as Partial<BackdropPreference> | null
  return { version: 1, enabled: saved?.version === 1 && saved.enabled === true }
}

export type Mood = {
  /** Average change of the quoted symbols, or null when none is quoted. */
  average: number | null
  /** The quoted symbol with the largest absolute change, if any. */
  mover?: { symbol: string; change: number }
}

/** Reads the watchlist's mood from fresh quotes only; cached quotes say nothing. */
export function readMood(symbols: string[], quotes: Record<string, Quote>, errors: Record<string, string>): Mood {
  let sum = 0
  let count = 0
  let mover: Mood['mover']
  for (const symbol of symbols) {
    const change = quotes[symbol]?.changePercent
    if (errors[symbol] || typeof change !== 'number' || !Number.isFinite(change)) continue
    sum += change
    count++
    if (!mover || Math.abs(change) > Math.abs(mover.change)) mover = { symbol, change }
  }
  return { average: count ? sum / count : null, mover }
}

// Colors follow the band: green up, red down, the logo's blue when flat or unknown.
const UP = '#2FB36B'
const DOWN = '#E5484D'
const FLAT = '#6AB0FF'

function escape(text: string): string {
  return text.replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`)
}

/**
 * The backdrop: a slow glow in the top-right corner tinted by the watchlist's
 * average change, and the day's largest mover set large and faint beneath it.
 * Everything sits in the corner, away from the conversation and the prompt: the root
 * fills any box and the nested drawing stays pinned to that corner.
 */
export function backdropScene(mood: Mood): string {
  const average = mood.average
  const flat = average === null || Math.abs(average) < 0.05
  const color = flat ? FLAT : average! > 0 ? UP : DOWN
  // Stronger days glow a little stronger, within a narrow, quiet range.
  const strength = flat ? 0 : Math.min(Math.abs(average!) / 3, 1)
  const light = (0.16 + strength * 0.16).toFixed(3)
  const dark = (0.22 + strength * 0.2).toFixed(3)
  const mover = mood.mover && Math.abs(mood.mover.change) >= 0.01
    ? `${escape(mood.mover.symbol)} ${escape(formatChange(mood.mover.change))}` : ''
  return `<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%">
<style>
.base{fill:#F5F8FC}.glow{opacity:${light}}.mark{fill:#0B2A4D;fill-opacity:.055}
@media (prefers-color-scheme:dark){.base{fill:#07182E}.glow{opacity:${dark}}.mark{fill:#EAF3FF;fill-opacity:.06}}
@media (prefers-reduced-motion:no-preference){.breathe{animation:breathe 14s ease-in-out infinite;transform-origin:1300px 120px}}
@keyframes breathe{0%,100%{transform:scale(1)}50%{transform:scale(1.12)}}
</style>
<defs><radialGradient id="g"><stop offset="0" stop-color="${color}"/><stop offset=".55" stop-color="${color}" stop-opacity=".35"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></radialGradient></defs>
<rect class="base" width="100%" height="100%"/>
<svg width="100%" height="100%" viewBox="0 0 1600 1000" preserveAspectRatio="xMaxYMin meet">
<g class="breathe"><ellipse class="glow" cx="1300" cy="120" rx="560" ry="420" fill="url(#g)"/></g>
</svg>
${mover ? `<svg x="55%" width="45%" height="40%" viewBox="0 0 700 400" preserveAspectRatio="xMaxYMin meet">
<text class="mark" x="676" y="130" text-anchor="end" font-family="-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif" font-size="64" font-weight="700" letter-spacing="-1">${mover}</text>
</svg>` : ''}
</svg>`
}

export function sceneAlt(mood: Mood): string {
  if (mood.average === null) return 'A soft blue glow in the corner'
  const direction = Math.abs(mood.average) < 0.05 ? 'flat' : mood.average > 0 ? 'up' : 'down'
  const mover = mood.mover ? `, largest mover ${mood.mover.symbol} ${formatChange(mood.mover.change)}` : ''
  return `A soft glow showing the watchlist ${direction} on average${mover}`
}
