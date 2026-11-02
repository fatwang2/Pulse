// Symbols, the two quote sources and number formatting. No Herdr imports, so
// tests run it under Node. Ported from Pulse CC (plugins/claude-code/hooks).

// The only two hosts Pulse contacts.
export const YAHOO_CHART = "https://query1.finance.yahoo.com/v8/finance/chart/";
export const BINANCE_TICKERS = "https://data-api.binance.vision/api/v3/ticker/24hr";
export const BINANCE_KLINES = "https://data-api.binance.vision/api/v3/klines";
// The one page the mod opens, on a click (`open`, the system's browser), tagged
// with where the click came from.
export const PULSE_URLS = {
  panel: "https://www.pulseticker.app/?utm_source=herdr&utm_medium=mod&utm_content=panel",
  detail: "https://www.pulseticker.app/?utm_source=herdr&utm_medium=mod&utm_content=detail",
};
// Shown until the person saves a watchlist of their own.
export const STARTER_SYMBOLS = ["AAPL", "NVDA", "^GSPC", "BTC/USDT"];
export const BINANCE_BATCH = 100;

export class QuoteError extends Error {
  constructor(message, options = {}) {
    super(message);
    this.retryAfterMs = options.retryAfterMs;
    this.invalidSymbol = options.invalidSymbol === true;
  }
}

/** A Binance Spot pair is written BASE/QUOTE (BTC/USDT); a dash stays a Yahoo symbol (BTC-USD). */
export function isCryptoPair(symbol) {
  return /^[A-Z0-9]{1,20}\/[A-Z0-9]{1,20}$/.test(symbol);
}

/** Yahoo tickers or Binance pairs, never company names or URLs. Throws a message for people. */
export function normalizeSymbol(input) {
  let symbol = String(input ?? "").trim().toUpperCase();
  if (isCryptoPair(symbol)) return symbol;
  if (!/^[A-Z0-9^][A-Z0-9.^=\-]{0,31}$/.test(symbol)) {
    throw new QuoteError("Enter a ticker, such as AAPL, 0700.HK or ^GSPC, or a pair, such as BTC/USDT.");
  }
  if (/^\d{6}\.SH$/.test(symbol)) symbol = symbol.replace(/\.SH$/, ".SS");
  const hk = /^(\d{1,5})\.HK$/.exec(symbol);
  if (hk) symbol = String(Number(hk[1])).padStart(4, "0") + ".HK";
  return symbol;
}

const positive = (value) => typeof value === "number" && Number.isFinite(value) && value > 0;

const cleanText = (value) => typeof value === "string"
  ? value.replace(/[\u0000-\u001f\u007f-\u009f]/g, "").slice(0, 100) || null
  : null;

/** Today's 5-minute bars: the quote metadata and the intraday line in one request. */
export function yahooUrl(symbol) {
  return YAHOO_CHART + encodeURIComponent(normalizeSymbol(symbol)) + "?interval=5m&range=1d&includePrePost=false";
}

const finite = (value) => typeof value === "number" && Number.isFinite(value);
const MAX_POINTS = 400;

/** Finite closes in order; gaps (null bars) are dropped. */
function cleanSeries(values) {
  if (!Array.isArray(values)) return [];
  const series = values.filter((value) => positive(value));
  return series.length > MAX_POINTS ? series.slice(series.length - MAX_POINTS) : series;
}

const period = (value) => finite(value?.start) && finite(value?.end) && value.end > value.start
  ? [value.start * 1000, value.end * 1000] : null;

/** `response` is `{ status, ok, text }` with the body already read. */
export function decodeYahoo(symbol, response, now) {
  // Herdr's fetch does not expose headers, so Retry-After is unknown: wait at least a minute.
  if (response.status === 429) throw new QuoteError("Yahoo rate limited requests.", { retryAfterMs: 60_000 });
  if (response.status === 404) throw new QuoteError("Ticker not found on Yahoo Finance.");
  if (!response.ok) throw new QuoteError(`Yahoo returned HTTP ${response.status}.`);
  let body;
  try { body = JSON.parse(response.text); } catch { throw new QuoteError("Yahoo returned an unreadable response."); }
  const meta = body?.chart?.result?.[0]?.meta;
  if (body?.chart?.error || !meta) throw new QuoteError("No quote available for this ticker.");
  // Never show another instrument's response under the requested ticker.
  let returned = null;
  try { returned = typeof meta.symbol === "string" ? normalizeSymbol(meta.symbol) : null; } catch { /* checked below */ }
  if (returned !== symbol) throw new QuoteError("Yahoo returned a different ticker.");
  if (!positive(meta.regularMarketPrice) || !positive(meta.regularMarketTime)) {
    throw new QuoteError("Yahoo returned an incomplete quote.");
  }
  const close = positive(meta.previousClose) ? meta.previousClose : meta.chartPreviousClose;
  const delay = meta.exchangeDataDelayedBy;
  const bars = body.chart.result[0].indicators?.quote?.[0] ?? {};
  const series = cleanSeries(bars.close);
  const opens = cleanSeries(bars.open);
  const highs = cleanSeries(bars.high);
  const lows = cleanSeries(bars.low);
  const periods = meta.currentTradingPeriod ?? {};
  return {
    symbol,
    name: cleanText(meta.longName) ?? cleanText(meta.shortName) ?? symbol,
    price: meta.regularMarketPrice,
    changePercent: positive(close) ? (meta.regularMarketPrice - close) / close * 100 : null,
    currency: typeof meta.currency === "string" && /^[A-Z]{3}$/.test(meta.currency) ? meta.currency : null,
    timestamp: meta.regularMarketTime * 1000,
    fetchedAt: now,
    delaySeconds: typeof delay === "number" && Number.isFinite(delay) && delay >= 0 ? delay : null,
    series,
    open: opens[0] ?? null,
    high: positive(meta.regularMarketDayHigh) ? meta.regularMarketDayHigh : highs.length ? Math.max(...highs) : null,
    low: positive(meta.regularMarketDayLow) ? meta.regularMarketDayLow : lows.length ? Math.min(...lows) : null,
    previousClose: positive(close) ? close : null,
    periods: { pre: period(periods.pre), regular: period(periods.regular), post: period(periods.post) },
  };
}

/** One request for up to BINANCE_BATCH pairs: `?symbols=["BTCUSDT","ETHUSDT"]`. */
export function binanceUrl(pairs) {
  return `${BINANCE_TICKERS}?symbols=${encodeURIComponent(JSON.stringify(pairs.map((pair) => pair.replace("/", ""))))}`;
}

/** Quotes by requested pair; a pair Binance did not return is absent. */
export function decodeBinance(pairs, response, now) {
  // -1121 Invalid symbol: one unknown or delisted pair fails the whole batch.
  if (response.status === 400) throw new QuoteError("Binance has no Spot pair with this name.", { invalidSymbol: true });
  if (response.status === 429 || response.status === 418) throw new QuoteError("Binance rate limited requests.");
  if (!response.ok) throw new QuoteError(`Binance returned HTTP ${response.status}.`);
  let body;
  try { body = JSON.parse(response.text); } catch { throw new QuoteError("Binance returned an unreadable response."); }
  const wanted = new Map(pairs.map((pair) => [pair.replace("/", ""), pair]));
  const quotes = {};
  for (const ticker of Array.isArray(body) ? body : [body]) {
    const pair = typeof ticker?.symbol === "string" ? wanted.get(ticker.symbol) : undefined;
    if (!pair) continue;
    const price = Number(ticker.lastPrice);
    const close = Number(ticker.prevClosePrice);
    const time = Number(ticker.closeTime);
    if (!positive(price) || !positive(time)) continue;
    quotes[pair] = {
      symbol: pair,
      name: "Binance Spot",
      price,
      // Against the price 24 hours before the last trade.
      changePercent: positive(close) ? (price - close) / close * 100 : null,
      currency: pair.split("/")[1],
      timestamp: time,
      fetchedAt: now,
      delaySeconds: 0,
      series: [],
      open: positive(Number(ticker.openPrice)) ? Number(ticker.openPrice) : null,
      high: positive(Number(ticker.highPrice)) ? Number(ticker.highPrice) : null,
      low: positive(Number(ticker.lowPrice)) ? Number(ticker.lowPrice) : null,
      previousClose: positive(close) ? close : null,
      periods: null,
    };
  }
  return quotes;
}

/** The last 24 hours of one pair in 15-minute bars. */
export function binanceKlinesUrl(pair) {
  return `${BINANCE_KLINES}?symbol=${encodeURIComponent(pair.replace("/", ""))}&interval=15m&limit=96`;
}

/** Closing prices, oldest first; throws when Binance answers with anything else. */
export function decodeKlines(response) {
  if (!response.ok) throw new QuoteError(`Binance returned HTTP ${response.status}.`);
  let body;
  try { body = JSON.parse(response.text); } catch { throw new QuoteError("Binance returned an unreadable response."); }
  if (!Array.isArray(body)) throw new QuoteError("Binance returned an unreadable response.");
  return cleanSeries(body.map((bar) => Array.isArray(bar) ? Number(bar[4]) : NaN));
}

/** Where a stock's market is now: "pre", "open", "post" or "closed"; a pair trades around the clock. */
export function marketSession(quote, now) {
  if (!quote.periods) return "24h";
  const within = (range) => range && now >= range[0] && now < range[1];
  if (within(quote.periods.regular)) return "open";
  if (within(quote.periods.pre)) return "pre";
  if (within(quote.periods.post)) return "post";
  return "closed";
}

export const SESSION_LABELS = {
  open: "Market open", pre: "Pre-market", post: "After hours", closed: "Market closed", "24h": "Trades 24h",
};

/**
 * The line through `series`, scaled into its box as [x%, y%] points, and where
 * the reference price (the previous close) falls, or null when it is outside.
 * Fewer than two points draw nothing.
 */
export function chartGeometry(series, reference) {
  if (!Array.isArray(series) || series.length < 2) return null;
  const values = positive(reference) ? [...series, reference] : series;
  let min = Math.min(...values);
  let max = Math.max(...values);
  if (max - min < max * 1e-9) { min -= 1; max += 1; }
  // 8% headroom keeps the stroke inside the box.
  const pad = (max - min) * 0.08;
  min -= pad; max += pad;
  const y = (value) => Math.round((1 - (value - min) / (max - min)) * 10000) / 100;
  const last = series.length - 1;
  return {
    points: series.map((value, index) => [Math.round(index / last * 10000) / 100, y(value)]),
    reference: positive(reference) ? y(reference) : null,
  };
}

// Herdr's QuickJS runtime has no Intl, so numbers and dates are formatted by hand.
const group = (digits) => digits.replace(/\B(?=(\d{3})+(?!\d))/g, ",");

function significant(price) {
  // Below 1, keep 2 to 4 significant digits: 0.00000441 must not round to 0.000004.
  const places = Math.min(20, 3 - Math.floor(Math.log10(price)));
  let text = price.toFixed(places);
  const count = (s) => s.replace(".", "").replace(/^0+/, "").length;
  while (text.endsWith("0") && count(text) > 2) text = text.slice(0, -1);
  return text;
}

export function formatPrice(quote) {
  const [whole, fraction] = (quote.price < 1 ? significant(quote.price) : quote.price.toFixed(2)).split(".");
  const price = group(whole) + (fraction === undefined ? "" : "." + fraction);
  return quote.currency ? `${price} ${quote.currency}` : price;
}

/** The compact band leaves out USD and a pair's own quote currency. */
export function formatBandPrice(quote) {
  const named = quote.currency === "USD" || quote.symbol.endsWith(`/${quote.currency}`);
  return formatPrice(named ? { ...quote, currency: null } : quote);
}

export function formatChange(value) {
  return value === null || value === undefined ? "—" : `${value >= 0 ? "+" : ""}${value.toFixed(2)}%`;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** A quote from an earlier local day gets its date, so a closed market never reads as today's. */
export function formatStaleDate(timestamp, now) {
  const quoted = new Date(timestamp);
  const today = new Date(now);
  if (quoted.getFullYear() === today.getFullYear() && quoted.getMonth() === today.getMonth()
    && quoted.getDate() === today.getDate()) return "";
  return `${MONTHS[quoted.getMonth()]} ${quoted.getDate()}`;
}

/** Local wall-clock time, 24-hour: "15:04". */
export function formatTime(timestamp) {
  const date = new Date(timestamp);
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}
