import type { HttpResponse, Timer } from 'claude-code'
import { decodeQuote, normalizeSymbol, quotePath, YahooError } from './yahoo'
import type { Quote } from './yahoo'
import { BINANCE_BATCH, BinanceError, decodeTickers, isCryptoPair, tickersQuery } from './binance'

export const SETTINGS_KEY = 'watchlist.v1'
export type Preferences = { version: 1; symbols: string[]; paused: boolean }
export type Host = {
  load: () => Promise<unknown>
  save: (preferences: Preferences) => Promise<void>
  now: () => Promise<number>
  sleep: (ms: number) => Promise<void>
  after: (ms: number, callback: () => Promise<void>) => Timer
  fetchYahoo: (path: string) => Promise<HttpResponse>
  fetchBinance: (query: string) => Promise<HttpResponse>
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
  private pendingManual = false
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
    this.pendingManual = false
    this.timer?.cancel()
    this.timer = undefined
    this.loading = false
  }

  private changed(): void { this.api?.redraw() }

  private schedule(delay: number, manual = false): void {
    this.timer?.cancel()
    this.timer = undefined
    if (!this.active || (!manual && (this.preferences.paused || !this.preferences.symbols.length))) return
    if (this.job) { this.pending = true; this.pendingManual ||= manual; return }
    this.timer = this.api!.after(delay, async () => {
      this.timer = undefined
      await this.refresh(manual)
    })
  }

  private edit(change: (preferences: Preferences) => string): Promise<string> {
    const previous = this.writes
    const action = (async () => {
      try { await previous } catch { /* A failed write does not block the next. */ }
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
    })()
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
    const symbols = new Set(this.preferences.symbols)
    for (const record of [this.quotes, this.errors]) for (const key of Object.keys(record)) if (!symbols.has(key)) delete record[key]
  }

  async refresh(manual = true): Promise<void> {
    if (!this.active || !this.api) return
    if (this.job) return this.job
    this.timer?.cancel()
    this.timer = undefined
    this.pending = false
    this.pendingManual = false
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
      // Binance pairs keep their cadence through a Yahoo cooldown; Yahoo still waits.
      const crypto = this.preferences.symbols.some(isCryptoPair)
      if (this.pending) this.schedule(crypto ? 0 : cooldown, this.pendingManual)
      else this.schedule(Math.max(crypto ? 0 : cooldown, this.intervalMs))
    }
  }

  private async runRefresh(manual: boolean): Promise<void> {
    const now = await this.api!.now()
    if (now < this.retryAt) {
      // Binance pairs still refresh; Yahoo tickers wait out the cooldown.
      if (this.preferences.symbols.some(isCryptoPair)) await this.poll(manual, false)
      this.message = `Yahoo rate limited requests. Retry after ${Math.ceil((this.retryAt - now) / 1000)}s.`
      this.changed()
      return
    }
    await this.poll(manual)
  }

  private async request(path: string, current: () => boolean) {
    const api = this.api!
    const wait = 1000 - ((await api.now()) - this.lastRequestAt)
    if (wait > 0) await api.sleep(wait)
    if (!current()) return undefined
    this.lastRequestAt = await api.now()
    if (!current()) return undefined
    return api.fetchYahoo(path)
  }

  private async fetchQuote(symbol: string, current: () => boolean): Promise<void> {
    const response = await this.request(quotePath(symbol), current)
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

  private async poll(manual: boolean, yahoo = true): Promise<void> {
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
    const current = () => this.active && revision === this.revision
    const pairs = saved.symbols.filter(isCryptoPair)
    const tickers = saved.symbols.filter(symbol => !isCryptoPair(symbol))
    for (let offset = 0; offset < pairs.length; offset += BINANCE_BATCH) {
      await this.pollCrypto(pairs.slice(offset, offset + BINANCE_BATCH), current)
      if (!current()) return
    }
    if (!yahoo) return
    for (const symbol of tickers) {
      if (!this.active || revision !== this.revision) return
      try {
        await this.fetchQuote(symbol, () => this.active && revision === this.revision)
      } catch (error) {
        if (!this.active || revision !== this.revision) return
        // Do not echo request URLs or raw server bodies into the conversation.
        this.errors[symbol] = error instanceof YahooError ? error.message : 'Could not reach Yahoo Finance.'
        if (await this.throttle(error)) {
          const deferred = tickers.slice(tickers.indexOf(symbol) + 1)
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

  /** One request per batch; an unknown or delisted pair fails the batch, so retry pair by pair. */
  private async pollCrypto(pairs: string[], current: () => boolean): Promise<void> {
    try {
      await this.fetchCrypto(pairs, current)
    } catch (error) {
      if (!current()) return
      if (error instanceof BinanceError && error.invalidSymbol && pairs.length > 1) {
        for (const pair of pairs) {
          if (!current()) return
          try { await this.fetchCrypto([pair], current) } catch (cause) {
            if (!current()) return
            this.errors[pair] = cause instanceof BinanceError ? cause.message : 'Could not reach Binance.'
          }
        }
      } else {
        // Do not echo request URLs or raw server bodies into the conversation.
        for (const pair of pairs) this.errors[pair] = error instanceof BinanceError ? error.message : 'Could not reach Binance.'
      }
    }
    if (current()) this.changed()
  }

  private async fetchCrypto(pairs: string[], current: () => boolean): Promise<void> {
    const api = this.api!
    const response = await api.fetchBinance(tickersQuery(pairs))
    if (!current()) return
    const quotes = decodeTickers(pairs, response, await api.now())
    if (!current()) return
    for (const pair of pairs) {
      const quote = quotes[pair]
      if (quote) { this.quotes[pair] = quote; delete this.errors[pair] }
      else this.errors[pair] = 'Binance returned no quote for this pair.'
    }
  }
}
