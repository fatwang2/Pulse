import type { HttpResponse } from 'claude-code'
import type { Quote } from './yahoo'

// Binance's public market-data host (`data-api.binance.vision`), the same Spot
// source Pulse Mac uses. No key.
export const BINANCE_BATCH = 100

export class BinanceError extends Error {
  constructor(message: string, readonly invalidSymbol = false) {
    super(message)
  }
}

/** A Binance Spot pair is written BASE/QUOTE (BTC/USDT); a dash stays a Yahoo symbol (BTC-USD). */
export function isCryptoPair(symbol: string): boolean {
  return /^[A-Z0-9]{1,20}\/[A-Z0-9]{1,20}$/.test(symbol)
}

export function binanceSymbol(pair: string): string {
  return pair.replace('/', '')
}

/** The query of one request for up to BINANCE_BATCH pairs: `symbols=["BTCUSDT","ETHUSDT"]`. */
export function tickersQuery(pairs: string[]): string {
  return `symbols=${encodeURIComponent(JSON.stringify(pairs.map(binanceSymbol)))}`
}

const positive = (value: number): boolean => Number.isFinite(value) && value > 0

/** Quotes by requested pair; a pair Binance did not return is absent. */
export function decodeTickers(pairs: string[], response: HttpResponse, now: number): Record<string, Quote> {
  if (response.status === 400) {
    // -1121 Invalid symbol: one unknown or delisted pair fails the whole batch.
    throw new BinanceError('Binance has no Spot pair with this name.', true)
  }
  if (response.status === 429 || response.status === 418) throw new BinanceError('Binance rate limited requests.')
  if (!response.ok) throw new BinanceError(`Binance returned HTTP ${response.status}.`)
  let body: unknown
  try { body = JSON.parse(response.text) } catch { throw new BinanceError('Binance returned an unreadable response.') }
  const tickers = Array.isArray(body) ? body : [body]
  const wanted = new Map(pairs.map(pair => [binanceSymbol(pair), pair]))
  const quotes: Record<string, Quote> = {}
  for (const ticker of tickers as Record<string, unknown>[]) {
    const pair = typeof ticker?.symbol === 'string' ? wanted.get(ticker.symbol) : undefined
    if (!pair) continue
    const price = Number(ticker.lastPrice)
    const close = Number(ticker.prevClosePrice)
    const time = Number(ticker.closeTime)
    if (!positive(price) || !positive(time)) continue
    quotes[pair] = {
      symbol: pair,
      name: 'Binance Spot',
      price,
      // As in Pulse Mac: the change against the close 24 hours before the last trade.
      changePercent: positive(close) ? (price - close) / close * 100 : null,
      currency: pair.split('/')[1],
      timestamp: time,
      fetchedAt: now,
      // Binance Spot data is not delayed.
      delaySeconds: 0,
    }
  }
  return quotes
}
