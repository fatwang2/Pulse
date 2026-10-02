// Yahoo Finance v8 chart (unofficial API), ported from PulseCore's
// `YahooProvider.swift`.
//
// One source covering US, HK, Shanghai, Shenzhen, Tokyo, both Korean boards and
// the COMEX/NYMEX metal contracts. Crypto is deliberately absent: Binance is the
// sole source of truth for pairs, and Yahoo's spot metal symbols have never
// worked, so `XAU`/`XAG` are refused here rather than quietly priced off a
// futures contract that is not what the row asks for.

.import "SymbolID.js" as SymbolID

var ID = "yahoo"
var NAME = "Yahoo Finance"
var BASE = "https://query1.finance.yahoo.com/v8/finance/chart/"

// Per-market delay in seconds, as published or measured. Zero means the tape.
// Seoul measures ~21 minutes behind and Tokyo is licensed the same way; both
// round to the 20 minutes Yahoo states.
var DELAY = {
  us: 0, hk: 900, sh: 900, sz: 900, jp: 1200, kr: 1200, kq: 1200, metal: 600
}

var MARKETS = ["us", "hk", "sh", "sz", "jp", "kr", "kq", "metal"]

// Yahoo rate-limits hard per IP. One symbol per request, a second apart, and a
// 60-second cadence — liveliness is not this source's job.
var DESCRIPTOR = {
  id: ID,
  name: NAME,
  markets: MARKETS,
  capabilities: ["quotes", "candles"],
  delay: DELAY,
  rateLimit: { minIntervalMs: 1000, batchSize: 1 },
  suggestedPollIntervalMs: 60000
}

var INDEX_WIRE = {
  sp500: "^GSPC", nasdaqComposite: "^IXIC", dowJonesIndustrial: "^DJI",
  nasdaq100: "^NDX", vix: "^VIX", russell1000: "^RUI", russell2000: "^RUT",
  hangSeng: "^HSI", hangSengTech: "^HSTECH",
  shanghaiComposite: "000001.SS", shenzhenComponent: "399001.SZ", chiNext: "399006.SZ",
  nikkei225: "^N225", kospi: "^KS11"
}

var SUFFIX = { hk: ".HK", sh: ".SS", sz: ".SZ", jp: ".T", kr: ".KS", kq: ".KQ" }

function padded(code, width) {
  var value = String(code)
  while (value.length < width) value = "0" + value
  return value
}

// Yahoo's wire spelling for one identity. HK is padded back to four digits,
// which is the width Yahoo indexes; Pulse stores it unpadded.
function wireSymbol(symbol) {
  if (!symbol) return null
  if (SymbolID.isCrypto(symbol)) return null
  if (SymbolID.isMetal(symbol)) {
    // `=F` is Yahoo's continuous front-month futures notation. Spot has no
    // working symbol at all, so it is refused rather than approximated.
    if (SymbolID.isSpotMetal(symbol)) return null
    if (symbol.market === "metalCN") return null
    return SymbolID.code(symbol) + "=F"
  }
  if (SymbolID.isIndex(symbol)) return INDEX_WIRE[symbol.id] || null
  var code = SymbolID.code(symbol)
  if (symbol.market === "us") return code
  if (symbol.market === "hk") return padded(code, 4) + ".HK"
  var suffix = SUFFIX[symbol.market]
  return suffix ? code + suffix : null
}

// Yahoo's crypto notation is BASE-QUOTE against a small set of settlement
// assets. Testing the quote side is what separates `BTC-USD` from `BRK-B`.
var CRYPTO_QUOTE_ASSETS = ["USD", "USDT", "USDC", "BTC", "ETH", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF"]

function looksLikeCryptoPair(raw) {
  var parts = String(raw || "").split("-")
  if (parts.length !== 2) return false
  return CRYPTO_QUOTE_ASSETS.indexOf(parts[1]) >= 0
}

// The reverse of `wireSymbol`: what Yahoo calls a thing, turned back into an
// identity. Search returns wire symbols, so nothing from search can enter the
// watchlist without passing through here first.
function symbolFromWire(raw) {
  var upper = String(raw || "").replace(/^\s+|\s+$/g, "").toUpperCase()
  if (!upper) return null

  for (var id in INDEX_WIRE) {
    if (Object.prototype.hasOwnProperty.call(INDEX_WIRE, id) && INDEX_WIRE[id] === upper) {
      return SymbolID.create(SymbolID.INDEXES[id].market, SymbolID.INDEXES[id].code)
    }
  }

  // Metals are checked before the `=` rejection below: their futures notation
  // is the one Yahoo symbol shape with an `=` that Pulse understands.
  var metal = SymbolID.metalIDFor(upper)
  if (metal) return SymbolID.create(SymbolID.METALS[metal].market, SymbolID.METALS[metal].code)

  var suffixes = [[".HK", "hk", 3], [".SS", "sh", 3], [".SZ", "sz", 3],
                  [".T", "jp", 2], [".KS", "kr", 3], [".KQ", "kq", 3]]
  for (var i = 0; i < suffixes.length; i++) {
    var suffix = suffixes[i]
    if (upper.length > suffix[2] && upper.slice(-suffix[2]) === suffix[0]) {
      return SymbolID.create(suffix[1], upper.slice(0, upper.length - suffix[2]))
    }
  }

  // `BTC-USD` is Yahoo's crypto spelling, and it is refused rather than routed
  // here: Binance is the sole source of truth for pairs, and a US ticker
  // called BTC-USD would be a row this adapter can never price. Note that a
  // hyphen alone does not mean crypto — `BRK-B` is a share class.
  if (looksLikeCryptoPair(upper)) return null

  // Any other exchange suffix, FX pair or futures contract is a market Pulse
  // does not model. Refusing it is the honest answer; guessing US would put a
  // London or Frankfurt listing on the watchlist under an American badge.
  if (upper.indexOf(".") >= 0 || upper.indexOf("=") >= 0) return null
  return SymbolID.create("us", upper)
}

function supports(symbol) {
  return wireSymbol(symbol) !== null
}

// US symbols are read over a two-day, one-minute window with pre/post included,
// because that is the only shape that carries an extended-session price. Two
// days rather than one: during pre-market a one-day window makes
// `chartPreviousClose` the close *before* the last regular session, which is
// exactly the reference that session's own change needs.
function requestFor(symbol) {
  var wire = wireSymbol(symbol)
  if (!wire) return null
  var extended = symbol.market === "us"
  var query = extended
    ? "interval=1m&range=2d&includePrePost=true"
    // Five-minute bars give the row its intraday line and, unlike the daily
    // shape, consistently carry chartPreviousClose for the change figure.
    // It is still the same response and therefore costs no extra request.
    : "interval=5m&range=1d&includePrePost=false"
  return {
    url: BASE + encodeURIComponent(wire) + "?" + query,
    wireSymbol: wire,
    extended: extended
  }
}

function firstFinite(values) {
  if (!values) return null
  for (var i = 0; i < values.length; i++) {
    if (typeof values[i] === "number" && isFinite(values[i])) return values[i]
  }
  return null
}

function chartResult(payload) {
  var chart = payload && payload.chart
  if (!chart) return null
  if (chart.error) return null
  var results = chart.result
  return (results && results.length > 0) ? results[0] : null
}

function ohlcSeries(result) {
  var indicators = result && result.indicators
  var quotes = indicators && indicators.quote
  return (quotes && quotes.length > 0) ? quotes[0] : null
}

// The last bar that actually printed. Yahoo pads the window with null closes
// past the current time, so scanning backwards is the only way to find it.
function latestClose(result) {
  var timestamps = result && result.timestamp
  var series = ohlcSeries(result)
  var closes = series && series.close
  if (!timestamps || !closes) return null
  var count = Math.min(timestamps.length, closes.length)
  for (var i = count - 1; i >= 0; i--) {
    var close = closes[i]
    if (typeof close === "number" && isFinite(close)) {
      return { price: close, timestampMs: timestamps[i] * 1000 }
    }
  }
  return null
}

// The little line in a watchlist row needs prices, not full OHLC candles. For
// the two-day US request, keep only the current trading period; otherwise
// yesterday's line would be joined to today's pre-market with a false edge.
function intradaySeries(result, extended) {
  var timestamps = result && result.timestamp
  var series = ohlcSeries(result)
  var closes = series && series.close
  if (!timestamps || !closes) return null

  var periods = result.meta && result.meta.currentTradingPeriod
  var start = 0
  if (extended) {
    start = (periods && periods.pre && periods.pre.start)
      || (periods && periods.regular && periods.regular.start)
      || 0
  }

  var points = []
  var minimum = Infinity
  var maximum = -Infinity
  var count = Math.min(timestamps.length, closes.length)
  for (var i = 0; i < count; i++) {
    var close = closes[i]
    if (timestamps[i] < start || typeof close !== "number" || !isFinite(close)) continue
    points.push(close)
    minimum = Math.min(minimum, close)
    maximum = Math.max(maximum, close)
  }
  if (points.length < 2) return null
  return { points: points, min: minimum, max: maximum }
}

function withinPeriod(period, seconds) {
  return !!period && seconds >= period.start && seconds < period.end
}

function marketStateFor(timestampMs, periods) {
  var seconds = Math.floor(Number(timestampMs) / 1000)
  if (withinPeriod(periods && periods.pre, seconds)) return "preMarket"
  if (withinPeriod(periods && periods.regular, seconds)) return "regular"
  if (withinPeriod(periods && periods.post, seconds)) return "postMarket"
  return "closed"
}

// What the displayed change is measured against. In an extended session the
// reference is the regular close, so the number reads as "since the bell"
// rather than "since yesterday".
function referenceClose(state, regularPrice, previousClose, chartPreviousClose) {
  if (state === "preMarket" || state === "postMarket" || state === "overnight") return regularPrice
  if (typeof previousClose === "number" && isFinite(previousClose)) return previousClose
  if (typeof chartPreviousClose === "number" && isFinite(chartPreviousClose)) return chartPreviousClose
  return regularPrice
}

// The last completed regular session, attached to extended-session quotes so
// the row can show that day's result beside the live extended price.
// Pre-market: the day has not opened, so the last regular close *is*
// `previousClose`, and its own reference is the close before the window.
function regularSessionClose(state, regularPrice, previousClose, chartPreviousClose) {
  if (state === "preMarket") return { price: regularPrice, previousClose: chartPreviousClose }
  if (state === "postMarket" || state === "overnight") return { price: regularPrice, previousClose: previousClose }
  return null
}

// Today's regular open: the first bar at or after the regular period start.
// The window's first bar is yesterday's 04:00 pre-market print on a two-day
// range, and before the open there is no "today's open" to show at all.
function regularSessionOpen(result) {
  var periods = result.meta && result.meta.currentTradingPeriod
  var start = periods && periods.regular && periods.regular.start
  var timestamps = result.timestamp
  var series = ohlcSeries(result)
  var opens = series && series.open
  if (!start || !timestamps || !opens) return null
  var count = Math.min(timestamps.length, opens.length)
  for (var i = 0; i < count; i++) {
    if (timestamps[i] < start) continue
    if (typeof opens[i] === "number" && isFinite(opens[i])) return opens[i]
  }
  return null
}

// Parses one chart response into a quote. Returns null when the payload
// carries no price, which is Yahoo's way of saying the symbol does not exist.
function parseQuote(symbol, payload, extended) {
  var result = chartResult(payload)
  if (!result || !result.meta) return null
  var meta = result.meta
  var regularPrice = meta.regularMarketPrice
  if (typeof regularPrice !== "number" || !isFinite(regularPrice)) return null

  var nowMs = null
  var quote = {
    symbol: SymbolID.toString(symbol),
    market: symbol.market,
    name: meta.longName || meta.shortName || null,
    currencyCode: meta.currency || SymbolID.currencyCode(symbol),
    high: typeof meta.regularMarketDayHigh === "number" ? meta.regularMarketDayHigh : null,
    low: typeof meta.regularMarketDayLow === "number" ? meta.regularMarketDayLow : null,
    volume: typeof meta.regularMarketVolume === "number" ? meta.regularMarketVolume : null,
    turnover: null,
    sourceID: ID,
    sourceName: NAME,
    sourceDelaySeconds: DELAY[symbol.market] === undefined ? null : DELAY[symbol.market],
    regularSession: null,
    series: intradaySeries(result, extended)
  }

  if (!extended) {
    var previous = meta.previousClose
    if (typeof previous !== "number" || !isFinite(previous)) previous = meta.chartPreviousClose
    if (typeof previous !== "number" || !isFinite(previous)) previous = regularPrice
    var series = ohlcSeries(result)
    quote.price = regularPrice
    quote.previousClose = previous
    quote.open = firstFinite(series && series.open)
    quote.timestampMs = typeof meta.regularMarketTime === "number" ? meta.regularMarketTime * 1000 : null
    quote.marketState = "regular"
    return quote
  }

  var latest = latestClose(result)
  var regularTimeMs = typeof meta.regularMarketTime === "number" ? meta.regularMarketTime * 1000 : null
  var state = latest ? marketStateFor(latest.timestampMs, meta.currentTradingPeriod) : "regular"
  quote.price = latest ? latest.price : regularPrice
  quote.previousClose = referenceClose(state, regularPrice, meta.previousClose, meta.chartPreviousClose)
  quote.open = regularSessionOpen(result)
  quote.timestampMs = latest ? latest.timestampMs : regularTimeMs
  quote.marketState = state
  quote.regularSession = regularSessionClose(state, regularPrice, meta.previousClose, meta.chartPreviousClose)
  return quote
}

// --- Candles --------------------------------------------------------------
//
// Same chart endpoint as quotes, different window. The macOS app's periods:
// daily, weekly and monthly candlesticks; intraday is already on the quote as
// `series`, so it never needs a second request.

var CANDLE_PERIODS = {
  day: { interval: "1d", range: "6mo" },
  week: { interval: "1wk", range: "2y" },
  month: { interval: "1mo", range: "10y" }
}

function candleRequest(symbol, period) {
  var spec = CANDLE_PERIODS[String(period || "")]
  var wire = wireSymbol(symbol)
  if (!spec || !wire) return null
  return {
    url: BASE + encodeURIComponent(wire)
      + "?interval=" + spec.interval + "&range=" + spec.range + "&includePrePost=false",
    period: period
  }
}

// One candle per completed bar. Yahoo pads the tail with null rows and often
// appends a live, incomplete bar for the current period; the nulls are
// dropped, the live bar is kept — the macOS app shows it too, and a chart
// whose last candle is yesterday reads as stale.
function parseCandles(payload) {
  var result = chartResult(payload)
  if (!result) return null
  var timestamps = result.timestamp
  var series = ohlcSeries(result)
  if (!timestamps || !series) return null
  var opens = series.open || []
  var highs = series.high || []
  var lows = series.low || []
  var closes = series.close || []
  var volumes = series.volume || []

  var candles = []
  for (var i = 0; i < timestamps.length; i++) {
    var open = opens[i], high = highs[i], low = lows[i], close = closes[i]
    if (typeof open !== "number" || !isFinite(open)) continue
    if (typeof high !== "number" || !isFinite(high)) continue
    if (typeof low !== "number" || !isFinite(low)) continue
    if (typeof close !== "number" || !isFinite(close)) continue
    candles.push({
      timestampMs: timestamps[i] * 1000,
      open: open, high: high, low: low, close: close,
      volume: (typeof volumes[i] === "number" && isFinite(volumes[i])) ? volumes[i] : 0
    })
  }
  return candles.length > 0 ? candles : null
}

// --- Search ---------------------------------------------------------------

var SEARCH_URL = "https://query1.finance.yahoo.com/v1/finance/search"

// Yahoo indexes English names and tickers only. `任天堂`, `サムスン` and
// `삼성전자` all return nothing, and a 400 comes back for some non-Latin
// queries outright, so a Japanese or Korean stock is reached by its code until
// a native-language index is wired.
function searchRequest(query) {
  var text = String(query || "").replace(/^\s+|\s+$/g, "")
  if (!text) return null
  return {
    url: SEARCH_URL + "?q=" + encodeURIComponent(text)
      + "&quotesCount=12&newsCount=0&listsCount=0",
    query: text
  }
}

// Which Yahoo quote types can become a row. Every other future (`CL=F`,
// `MGC=F`) is dropped by the wire mapping anyway, but naming the types keeps
// currencies, options and Yahoo's own screeners out before that.
var SEARCHABLE_TYPES = {
  EQUITY: "equity", ETF: "etf", INDEX: "index", MUTUALFUND: "fund", FUTURE: "commodity"
}

// A query that is already a symbol needs no index. Yahoo cannot find
// `600519.SH` — that is Pulse's spelling, not its own — and answers 400 to
// Chinese, Japanese and Korean text outright, so without this the codes those
// users are told to fall back on would be the codes that do not work. Both
// spellings resolve, and neither costs a request.
function directMatch(query) {
  var text = String(query || "").replace(/^\s+|\s+$/g, "")
  if (!text) return null

  var symbol = SymbolID.parse(text) || symbolFromWire(text)
  if (!symbol) return null

  // A bare US ticker is indistinguishable from an English word — `nvidia`
  // parses as a ten-character US code perfectly well — so it is left to the
  // index, which answers it correctly. A direct match is for queries that name
  // their venue: a suffix, a crypto pair, or an index the index cannot find.
  var namesItsVenue = text.indexOf(".") >= 0 || text.indexOf("/") >= 0
  if (!namesItsVenue && symbol.kind === SymbolID.KIND_SECURITY && symbol.market === "us") return null
  // It still has to be an instrument this provider can price; otherwise the
  // row would join the watchlist and never quote.
  if (!supports(symbol)) return null

  return {
    key: SymbolID.toString(symbol),
    symbol: symbol,
    displayCode: SymbolID.displayCode(symbol),
    market: symbol.market,
    name: null,
    exchangeName: null,
    type: "direct"
  }
}

function parseSearch(payload, query) {
  var quotes = payload && payload.quotes
  var results = []
  var seen = {}

  // A code the user typed outright leads, because they already know what they
  // want; the index is there for the times they do not.
  var direct = directMatch(query)
  if (direct) {
    results.push(direct)
    seen[direct.key] = true
  }

  if (!quotes || typeof quotes.length !== "number") return results
  for (var i = 0; i < quotes.length; i++) {
    var item = quotes[i] || {}
    var type = SEARCHABLE_TYPES[String(item.quoteType || "").toUpperCase()]
    if (!type) continue
    var symbol = symbolFromWire(item.symbol)
    if (!symbol) continue
    var key = SymbolID.toString(symbol)
    if (seen[key]) {
      // The index knows the name for a code the user typed; the direct entry
      // is the same instrument, so it takes the better label rather than
      // appearing twice.
      for (var j = 0; j < results.length; j++) {
        if (results[j].key === key && !results[j].name) {
          results[j].name = item.longname || item.shortname || key
          results[j].exchangeName = item.exchDisp || null
        }
      }
      continue
    }
    seen[key] = true
    results.push({
      key: key,
      symbol: symbol,
      displayCode: SymbolID.displayCode(symbol),
      market: symbol.market,
      name: item.longname || item.shortname || key,
      exchangeName: item.exchDisp || null,
      type: type
    })
  }
  return results
}

if (typeof module !== "undefined") module.exports = {
  ID: ID,
  NAME: NAME,
  DESCRIPTOR: DESCRIPTOR,
  DELAY: DELAY,
  wireSymbol: wireSymbol,
  symbolFromWire: symbolFromWire,
  looksLikeCryptoPair: looksLikeCryptoPair,
  searchRequest: searchRequest,
  directMatch: directMatch,
  parseSearch: parseSearch,
  SEARCHABLE_TYPES: SEARCHABLE_TYPES,
  supports: supports,
  requestFor: requestFor,
  CANDLE_PERIODS: CANDLE_PERIODS,
  candleRequest: candleRequest,
  parseCandles: parseCandles,
  parseQuote: parseQuote,
  latestClose: latestClose,
  marketStateFor: marketStateFor,
  referenceClose: referenceClose,
  regularSessionClose: regularSessionClose,
  regularSessionOpen: regularSessionOpen,
  intradaySeries: intradaySeries
}
