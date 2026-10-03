import type { HttpResponse, McpToolResult, Timer } from 'claude-code'
import { decodeQuote, normalizeSymbol, quoteURL, YahooError } from './yahoo'
import type { Quote } from './yahoo'
import { decodeMacQuotes, decodeWatchlists, instruments, MacError, readMacPreferences, symbolKey } from './mac'
import type { MacGroup, MacPreferences, SymbolRef } from './mac'

export const SETTINGS_KEY = 'watchlist.v1'
export type Preferences = { version: 1; symbols: string[]; paused: boolean }
export type Host = {
  load: () => Promise<unknown>
  save: (preferences: Preferences) => Promise<void>
  loadMac: () => Promise<unknown>
  saveMac: (preferences: MacPreferences) => Promise<void>
  listMac: () => Promise<McpToolResult>
  quoteMac: (symbols: SymbolRef[]) => Promise<McpToolResult>
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
  macPreferences: MacPreferences = { version: 1, source: 'cc', selected: [] }
  groups: MacGroup[] = []
  macConnected = false
  private ccQuotes: Record<string, Quote> = {}
  private macQuotes: Record<string, Quote> = {}
  private ccErrors: Record<string, string> = {}
  private macErrors: Record<string, string> = {}
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

  constructor(private readonly intervalMs: number, private readonly macIntervalMs = 5000) {}

  get source(): 'cc' | 'mac' { return this.macPreferences.source }
  get symbols(): string[] {
    if (this.source === 'cc') return this.preferences.symbols
    const available = instruments(this.groups)
    return this.macPreferences.selected.map(symbolKey).filter(key => available.has(key))
  }
  get quotes(): Record<string, Quote> { return this.source === 'cc' ? this.ccQuotes : this.macQuotes }
  get errors(): Record<string, string> { return this.source === 'cc' ? this.ccErrors : this.macErrors }
  label(key: string): string {
    const item = instruments(this.groups).get(key)
    return this.source === 'mac' && item ? `${item.displayCode} ${item.market.toUpperCase()}` : key
  }

  async start(api: Host): Promise<void> {
    this.stop()
    this.api = api
    this.preferences = readPreferences(await api.load())
    this.macPreferences = readMacPreferences(await api.loadMac())
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
    if (!this.active || (!manual && (this.preferences.paused || (this.source === 'cc' && !this.preferences.symbols.length)))) return
    if (this.job) { this.pending = true; this.pendingManual ||= manual; return }
    this.timer = this.api!.after(delay, async () => {
      this.timer = undefined
      await this.refresh(manual)
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
    if (this.source === 'mac') return Promise.reject(new Error('Add tickers in Pulse Mac, then select them here.'))
    const symbol = normalizeSymbol(input)
    return this.edit(preferences => {
      if (preferences.symbols.includes(symbol)) return `${symbol} is already on your watchlist.`
      preferences.symbols.push(symbol)
      return `Added ${symbol}.`
    })
  }

  remove(input: string): Promise<string> {
    if (this.source === 'mac') return Promise.reject(new Error('Uncheck a ticker to hide it here. Manage the watchlist in Pulse Mac.'))
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

  private editMac(change: (preferences: MacPreferences) => string, manual = false): Promise<string> {
    const action = this.writes.catch(() => {}).then(async () => {
      if (!this.api) throw new Error('Pulse has not started yet.')
      const preferences = readMacPreferences(await this.api.loadMac())
      const message = change(preferences)
      await this.api.saveMac(preferences)
      this.macPreferences = preferences
      this.revision++
      this.message = message
      this.reconcile()
      this.changed()
      this.schedule(0, manual)
      return message
    })
    this.writes = action
    return action
  }

  async setSource(source: 'cc' | 'mac'): Promise<string> {
    return this.editMac(preferences => {
      preferences.source = source
      return source === 'mac' ? 'Pulse Mac selected. Choose tickers to display.' : 'Claude Code watchlist selected.'
    }, source === 'mac') // One read makes groups available even when paused.
  }

  toggleMac(symbol: SymbolRef): Promise<string> {
    if (this.source !== 'mac') return Promise.reject(new Error('Select Pulse Mac first.'))
    const key = symbolKey(symbol)
    if (!instruments(this.groups).has(key)) return Promise.reject(new Error('This ticker is no longer in Pulse Mac. Refresh the list.'))
    return this.editMac(preferences => {
      const selected = preferences.selected.some(ref => symbolKey(ref) === key)
      preferences.selected = selected ? preferences.selected.filter(ref => symbolKey(ref) !== key) : [...preferences.selected, symbol]
      return selected ? 'Ticker hidden in Claude Code.' : 'Ticker selected for Claude Code.'
    })
  }

  private reconcile(): void {
    const ccSymbols = new Set(this.preferences.symbols)
    const macSymbols = new Set(instruments(this.groups).keys())
    for (const [records, keys] of [
      [[this.ccQuotes, this.ccErrors], ccSymbols], [[this.macQuotes, this.macErrors], macSymbols],
    ] as const) {
      for (const record of records) for (const key of Object.keys(record)) if (!keys.has(key)) delete record[key]
    }
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
      const cooldown = this.source === 'cc' ? Math.max(0, this.retryAt - now) : 0
      if (this.pending) this.schedule(cooldown, this.pendingManual)
      else this.schedule(this.source === 'mac' ? this.macIntervalMs : Math.max(cooldown, this.intervalMs))
    }
  }

  private async runRefresh(manual: boolean): Promise<void> {
    const now = await this.api!.now()
    if (this.source === 'cc' && now < this.retryAt) {
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
    this.ccQuotes[symbol] = decodeQuote(symbol, response, now)
    delete this.ccErrors[symbol]
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
    const mac = readMacPreferences(await api.loadMac())
    if (!this.active || revision !== this.revision) return
    // Pick up changes made in another local Claude Code session.
    this.preferences = saved
    this.macPreferences = mac
    this.reconcile()
    if (saved.paused && !manual) { this.changed(); return }
    if (this.source === 'mac') return this.pollMac(revision)
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
        this.ccErrors[symbol] = error instanceof YahooError ? error.message : 'Could not reach Yahoo Finance.'
        if (await this.throttle(error)) {
          const deferred = saved.symbols.slice(saved.symbols.indexOf(symbol) + 1)
          for (const remaining of deferred) this.ccErrors[remaining] = 'Refresh deferred: Yahoo rate limited requests.'
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

  private async pollMac(revision: number): Promise<void> {
    const api = this.api!
    const current = () => this.active && revision === this.revision && this.source === 'mac'
    this.loading = true
    this.message = ''
    this.changed()
    try {
      const result = await api.listMac()
      if (!current()) return
      this.groups = decodeWatchlists(result)
      this.reconcile()
      this.macConnected = true
      this.changed()
      const available = instruments(this.groups)
      const selected = this.symbols.map(key => available.get(key)!)
      for (let offset = 0; offset < selected.length; offset += 100) {
        const batch = selected.slice(offset, offset + 100)
        const result = await api.quoteMac(batch.map(({ market, code }) => ({ market, code })))
        const now = await api.now()
        if (!current()) return
        for (const [key, quote] of Object.entries(decodeMacQuotes(result, batch, now))) {
          if (quote) { this.macQuotes[key] = quote; delete this.macErrors[key] }
          else this.macErrors[key] = 'No quote cached in Pulse Mac yet.'
        }
      }
    } catch (error) {
      if (!current()) return
      this.macConnected = false
      this.message = error instanceof MacError ? error.message
        : 'Could not reach Pulse Mac. Keep the app open and check its MCP connection in /mcp.'
      for (const key of this.symbols) this.macErrors[key] = this.message
    }
    if (current()) this.changed()
  }
}
