import type { McpToolResult } from 'claude-code'
import type { Quote } from './yahoo'

export const MAC_SETTINGS_KEY = 'mac-view.v1'
export type SymbolRef = { market: string; code: string }
export type MacInstrument = SymbolRef & { displayCode: string; name: string }
export type MacGroup = { id: string; name: string; symbols: MacInstrument[] }
export type MacPreferences = { version: 1; source: 'cc' | 'mac'; selected: SymbolRef[] }

export class MacError extends Error {}

export const symbolKey = (symbol: SymbolRef): string => `${symbol.market}:${symbol.code}`
const text = (value: unknown): string | undefined => typeof value === 'string'
  ? value.replace(/[\u0000-\u001f\u007f-\u009f]/g, '').slice(0, 100).trim() || undefined : undefined
const object = (value: unknown): Record<string, unknown> | undefined =>
  value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : undefined

function reference(value: unknown): SymbolRef | undefined {
  const item = object(value)
  const market = text(item?.market), code = text(item?.code)
  if (!market || !/^[a-z][a-zA-Z0-9_-]{0,31}$/.test(market) || !code || market !== item?.market || code !== item?.code) return undefined
  return { market, code }
}

export function readMacPreferences(value: unknown): MacPreferences {
  const saved = object(value)
  const selected: SymbolRef[] = []
  const seen = new Set<string>()
  if (saved?.version === 1 && Array.isArray(saved.selected)) {
    for (const value of saved.selected) {
      const ref = reference(value)
      if (ref && !seen.has(symbolKey(ref))) { selected.push(ref); seen.add(symbolKey(ref)) }
    }
  }
  return { version: 1, source: saved?.version === 1 && saved.source === 'mac' ? 'mac' : 'cc', selected }
}

function payload(result: McpToolResult): unknown {
  if (result.isError) throw new MacError('Pulse Mac could not read this data. Check its Agent access settings.')
  if (result.structuredContent !== undefined) return result.structuredContent
  const content = result.content.filter(block => block.type === 'text').map(block => block.text ?? '').join('')
  try { return JSON.parse(content) } catch { throw new MacError('Pulse Mac returned an unreadable response.') }
}

export function decodeWatchlists(result: McpToolResult): MacGroup[] {
  const data = object(payload(result))
  if (!Array.isArray(data?.groups)) throw new MacError('Pulse Mac returned an invalid watchlist.')
  const ids = new Set<string>()
  return data.groups.map(value => {
    const group = object(value)
    const id = text(group?.id), name = text(group?.name)
    if (!id || ids.has(id) || !name || !Array.isArray(group?.symbols)) {
      throw new MacError('Pulse Mac returned an invalid watchlist group.')
    }
    ids.add(id)
    const seen = new Set<string>()
    const symbols = group.symbols.map(value => {
      const item = object(value), ref = reference(value)
      if (!ref || seen.has(symbolKey(ref))) throw new MacError('Pulse Mac returned an invalid instrument.')
      seen.add(symbolKey(ref))
      return { ...ref, displayCode: text(item?.displayCode) ?? ref.code, name: text(item?.name) ?? ref.code }
    })
    return { id, name, symbols }
  })
}

export function instruments(groups: MacGroup[]): Map<string, MacInstrument> {
  return new Map(groups.flatMap(group => group.symbols.map(item => [symbolKey(item), item] as const)))
}

/** Match every response to its requested market/code; never label another instrument's quote. */
export function decodeMacQuotes(result: McpToolResult, requested: MacInstrument[], now: number): Record<string, Quote | null> {
  const data = payload(result)
  if (!Array.isArray(data)) throw new MacError('Pulse Mac returned invalid quotes.')
  const expected = new Map(requested.map(item => [symbolKey(item), item]))
  const quotes: Record<string, Quote | null> = Object.fromEntries([...expected.keys()].map(key => [key, null]))
  const seen = new Set<string>()
  for (const value of data) {
    const item = object(value), ref = reference(item?.symbol)
    const key = ref ? symbolKey(ref) : ''
    const instrument = expected.get(key)
    if (!instrument || seen.has(key)) throw new MacError('Pulse Mac returned quotes for a different instrument.')
    seen.add(key)
    if (item?.quote === null) continue
    const quote = object(item?.quote)
    const timestamp = typeof quote?.timestamp === 'string' ? Date.parse(quote.timestamp) : NaN
    if (!quote || typeof quote.price !== 'number' || !Number.isFinite(quote.price) || quote.price <= 0
      || !Number.isFinite(timestamp) || timestamp <= 0) {
      throw new MacError('Pulse Mac returned an incomplete quote.')
    }
    quotes[key] = {
      symbol: key, name: instrument.name, price: quote.price,
      changePercent: typeof quote.previousClose === 'number' && Number.isFinite(quote.previousClose) && quote.previousClose > 0
        && typeof quote.changePercent === 'number' && Number.isFinite(quote.changePercent) ? quote.changePercent : null,
      currency: typeof quote.currencyCode === 'string' && /^[A-Z]{3}$/.test(quote.currencyCode) ? quote.currencyCode : null,
      timestamp, fetchedAt: now, delaySeconds: null,
    }
  }
  return quotes
}
