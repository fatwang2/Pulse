import type { HttpResponse } from 'claude-code'

export type Quote = {
  symbol: string
  name: string
  price: number
  changePercent: number | null
  currency: string | null
  timestamp: number
  fetchedAt: number
  delaySeconds: number | null
}

export class YahooError extends Error {
  constructor(message: string, readonly retryAfterMs?: number) {
    super(message)
  }
}

/** Yahoo wire symbols, not company names. Never interpolate arbitrary URLs. */
export function normalizeSymbol(input: string): string {
  let symbol = input.trim().toUpperCase()
  if (!/^[A-Z0-9^][A-Z0-9.^=\-]{0,31}$/.test(symbol)) {
    throw new Error('Enter a Yahoo ticker, such as AAPL, 0700.HK or ^GSPC.')
  }
  if (/^\d{6}\.SH$/.test(symbol)) symbol = symbol.replace(/\.SH$/, '.SS')
  const hk = /^(\d{1,5})\.HK$/.exec(symbol)
  if (hk) symbol = String(Number(hk[1])).padStart(4, '0') + '.HK'
  return symbol
}

/** Only quote metadata is used; daily bars avoid unnecessary minute-history payloads. */
export function quoteURL(symbol: string): string {
  return 'https://query1.finance.yahoo.com/v8/finance/chart/'
    + encodeURIComponent(normalizeSymbol(symbol)) + '?interval=1d&range=1d&includePrePost=false'
}

const positive = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value) && value > 0

const cleanText = (value: unknown): string | null => typeof value === 'string'
  ? value.replace(/[\u0000-\u001f\u007f-\u009f]/g, '').slice(0, 100) || null
  : null

function readResult(symbol: string, response: HttpResponse, now: number): any {
  if (response.status === 429) {
    const retry = response.headers['retry-after']
    const seconds = retry === undefined || retry.trim() === '' ? NaN : Number(retry)
    const wait = Number.isFinite(seconds) && seconds >= 0
      ? seconds * 1000 : Math.max(0, Date.parse(retry ?? '') - now)
    throw new YahooError('Yahoo rate limited requests.', Math.max(60_000, Number.isFinite(wait) ? wait : 60_000))
  }
  if (response.status === 404) throw new YahooError('Ticker not found on Yahoo Finance.')
  if (!response.ok) throw new YahooError(`Yahoo returned HTTP ${response.status}.`)
  let body: any
  try { body = JSON.parse(response.text) } catch { throw new YahooError('Yahoo returned an unreadable response.') }
  const result = body?.chart?.result?.[0]
  const meta = result?.meta
  if (body?.chart?.error || !meta) throw new YahooError('No quote available for this ticker.')
  // Never display the response for another instrument under the requested ticker.
  if (typeof meta.symbol !== 'string' || normalizeSymbol(meta.symbol) !== symbol) {
    throw new YahooError('Yahoo returned a different ticker.')
  }
  return result
}

export function decodeQuote(symbol: string, response: HttpResponse, now: number): Quote {
  const meta = readResult(symbol, response, now).meta
  if (!positive(meta.regularMarketPrice) || !positive(meta.regularMarketTime)) {
    throw new YahooError('Yahoo returned an incomplete quote.')
  }
  const close = positive(meta.previousClose) ? meta.previousClose : meta.chartPreviousClose
  const delay = meta.exchangeDataDelayedBy
  return {
    symbol,
    name: cleanText(meta.longName) ?? cleanText(meta.shortName) ?? symbol,
    price: meta.regularMarketPrice,
    changePercent: positive(close) ? (meta.regularMarketPrice - close) / close * 100 : null,
    currency: typeof meta.currency === 'string' && /^[A-Z]{3}$/.test(meta.currency) ? meta.currency : null,
    timestamp: meta.regularMarketTime * 1000,
    fetchedAt: now,
    delaySeconds: typeof delay === 'number' && Number.isFinite(delay) && delay >= 0 ? delay : null,
  }
}

export function formatPrice(quote: Quote): string {
  const price = quote.price.toLocaleString('en-US', {
    minimumFractionDigits: 2, maximumFractionDigits: quote.price < 1 ? 6 : 2,
  })
  return `${price}${quote.currency ? ' ' + quote.currency : ''}`
}

/** Keep the compact prompt ticker concise while disambiguating other currencies. */
export function formatBandPrice(quote: Quote): string {
  return formatPrice(quote.currency === 'USD' ? { ...quote, currency: null } : quote)
}

export function formatChange(value: number | null): string {
  return value === null ? '—' : `${value >= 0 ? '+' : ''}${value.toFixed(2)}%`
}

export function formatTime(timestamp: number): string {
  return new Date(timestamp).toLocaleString('en-US', {
    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false,
  })
}
