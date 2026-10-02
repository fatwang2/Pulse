import type { HttpResponse, Timer } from 'claude-code'
import { decodeQuote, normalizeSymbol, quoteURL, YahooError } from './yahoo'
import type { Quote } from './yahoo'

export const SETTINGS_KEY = 'watchlist.v1'
export type Preferences = { version: 1; symbols: string[]; paused: boolean }
export type Host = {
  load: () => Promise<unknown>
  save: (preferences: Preferences) => Promise<void>
  now: () => Promise<number>
  sleep: (ms: number) => Promise<void>
  after: (ms: number, callback: () => Promise<void>) => Timer
  fetch: (url: string) => Promise<HttpResponse>
  redraw: () => void
}

export function readPreferences(value: unknown): Preferences {
  const saved = value as Partial<Preferences> | null
  const symbols: string[] = []
  if (saved?.version === 1 && Array.isArray(saved.symbols)) {
    for (const raw of saved.symbols) {
      if (typeof raw !== 'string') continue
      try {
        const symbol = normalizeSymbol(raw)
        if (!symbols.includes(symbol)) symbols.push(symbol)
      } catch { /* Ignore invalid saved entries, not the whole watchlist. */ }
    }
  }
  return { version: 1, symbols, paused: saved?.version === 1 && saved.paused === true }
}

/** One controller per loaded mod; host APIs provide network, timers and storage. */
export class Watchlist {
  preferences: Preferences = { version: 1, symbols: [], paused: false }
  quotes: Record<string, Quote> = {}
  errors: Record<string, string> = {}
  message = ''
  loading = false
  retryAt = 0
  private api?: Host
  private timer?: Timer
  private active = false
  private revision = 0
  private job?: Promise<void>
  private pending = false
  private lastRequestAt = -Infinity
  private rateFailures = 0
  private writes: Promise<unknown> = Promise.resolve()

  constructor(private readonly intervalMs: number) {}

  async start(api: Host): Promise<void> {
    this.stop()
    this.api = api
    this.preferences = readPreferences(await api.load())
    this.reconcile()
    this.active = true
    this.changed()
    this.schedule(0)
  }

  stop(): void {
    this.active = false
    this.revision++
    this.pending = false
    this.timer?.cancel()
    this.timer = undefined
    this.loading = false
  }

  private changed(): void { this.api?.redraw() }

  private schedule(delay: number): void {
    this.timer?.cancel()
    this.timer = undefined
    if (!this.active || this.preferences.paused || !this.preferences.symbols.length) return
    if (this.job) { this.pending = true; return }
    this.timer = this.api!.after(delay, async () => {
      this.timer = undefined
      await this.refresh(false)
    })
  }

  private edit(change: (preferences: Preferences) => string): Promise<string> {
    const action = this.writes.catch(() => {}).then(async () => {
      if (!this.api) throw new Error('Pulse has not started yet.')
      // Read before writing so a second session's latest settings are retained.
      const preferences = readPreferences(await this.api.load())
      const message = change(preferences)
      await this.api.save(preferences)
      this.preferences = preferences
      this.revision++
      this.message = message
      this.reconcile()
      this.changed()
      this.schedule(0)
      return message
    })
    this.writes = action
    return action
  }

  add(input: string): Promise<string> {
    const symbol = normalizeSymbol(input)
    return this.edit(preferences => {
      if (preferences.symbols.includes(symbol)) return `${symbol} is already on your watchlist.`
      preferences.symbols.push(symbol)
      return `Added ${symbol}.`
    })
  }

  remove(input: string): Promise<string> {
    const symbol = normalizeSymbol(input)
    return this.edit(preferences => {
      if (!preferences.symbols.includes(symbol)) return `${symbol} is not on your watchlist.`
      preferences.symbols = preferences.symbols.filter(value => value !== symbol)
      return `Removed ${symbol}.`
    })
  }

  pause(paused: boolean): Promise<string> {
    return this.edit(preferences => {
      preferences.paused = paused
      return paused ? 'Automatic refresh paused.' : 'Automatic refresh resumed.'
    })
  }

  private reconcile(): void {
    const symbols = this.preferences.symbols
    for (const record of [this.quotes, this.errors]) {
      for (const key of Object.keys(record)) if (!symbols.includes(key)) delete record[key]
    }
  }

  async refresh(manual = true): Promise<void> {
    if (!this.active || !this.api) return
    if (this.job) return this.job
    this.timer?.cancel()
    this.timer = undefined
    this.pending = false
    // Claim the job before the first await; simultaneous refreshes share it.
    this.job = this.runRefresh(manual).catch(() => {
      this.message = 'Refresh failed. Try again with /pulse refresh.'
      this.changed()
    })
    try { await this.job } finally {
      this.job = undefined
      this.loading = false
      this.changed()
      const now = await this.api.now()
      const cooldown = Math.max(0, this.retryAt - now)
      if (this.pending) this.schedule(cooldown)
      else this.schedule(Math.max(cooldown, this.intervalMs))
    }
  }

  private async runRefresh(manual: boolean): Promise<void> {
    const now = await this.api!.now()
    if (now < this.retryAt) {
      this.message = `Yahoo rate limited requests. Retry after ${Math.ceil((this.retryAt - now) / 1000)}s.`
      this.changed()
      return
    }
    await this.poll(manual)
  }

  private async request(url: string, current: () => boolean) {
    const api = this.api!
    const wait = 1000 - ((await api.now()) - this.lastRequestAt)
    if (wait > 0) await api.sleep(wait)
    if (!current()) return undefined
    this.lastRequestAt = await api.now()
    if (!current()) return undefined
    return api.fetch(url)
  }

  private async fetchQuote(symbol: string, current: () => boolean): Promise<void> {
    const response = await this.request(quoteURL(symbol), current)
    if (!response || !current()) return
    const now = await this.api!.now()
    if (!current()) return
    this.quotes[symbol] = decodeQuote(symbol, response, now)
    delete this.errors[symbol]
  }

  private async throttle(cause: unknown): Promise<boolean> {
    if (!(cause instanceof YahooError) || cause.retryAfterMs === undefined) return false
    this.rateFailures++
    const backoff = Math.min(900_000, 60_000 * 2 ** Math.min(this.rateFailures - 1, 4))
    this.retryAt = (await this.api!.now()) + Math.max(backoff, cause.retryAfterMs)
    this.message = 'Yahoo rate limited requests. Automatic retries are delayed.'
    return true
  }

  private async poll(manual: boolean): Promise<void> {
    const api = this.api!
    const revision = this.revision
    const saved = readPreferences(await api.load())
    if (!this.active || revision !== this.revision) return
    // Pick up changes made in another local Claude Code session.
    this.preferences = saved
    this.reconcile()
    if (saved.paused && !manual) { this.changed(); return }
    this.loading = true
    this.message = ''
    this.changed()
    for (const symbol of [...saved.symbols]) {
      if (!this.active || revision !== this.revision) return
      try {
        await this.fetchQuote(symbol, () => this.active && revision === this.revision)
      } catch (error) {
        if (!this.active || revision !== this.revision) return
        // Do not echo request URLs or raw server bodies into the conversation.
        this.errors[symbol] = error instanceof YahooError ? error.message : 'Could not reach Yahoo Finance.'
        if (await this.throttle(error)) {
          const deferred = saved.symbols.slice(saved.symbols.indexOf(symbol) + 1)
          for (const remaining of deferred) this.errors[remaining] = 'Refresh deferred: Yahoo rate limited requests.'
          this.changed()
          return
        }
      }
      this.changed()
    }
    if (!this.active || revision !== this.revision) return
    this.rateFailures = 0
    this.retryAt = 0
  }
}
