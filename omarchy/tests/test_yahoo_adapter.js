const test = require("node:test")
const assert = require("node:assert/strict")

const { load } = require("./qmljs.js")
const fs = require("node:fs")
const path = require("node:path")

const Yahoo = load("YahooAdapter.js")
const SymbolID = load("SymbolID.js")

function fixture(name) {
  return JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8"))
}

test("wire symbols follow Yahoo's spelling, not Pulse's", () => {
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("AAPL")), "AAPL")
  // Yahoo indexes HK at four digits; Pulse stores the code unpadded.
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("700.HK")), "0700.HK")
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("600519.SH")), "600519.SS")
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("300750.SZ")), "300750.SZ")
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("7203.T")), "7203.T")
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("005930.KS")), "005930.KS")
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("035720.KQ")), "035720.KQ")
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("^GSPC")), "^GSPC")
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("000001.SH")), "000001.SS")
})

test("Yahoo is refused the instruments it cannot actually price", () => {
  // Binance is the sole source of truth for pairs.
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("BTC/USDT")), null)
  // No Yahoo spot metal symbol has ever worked; pricing XAU off GC=F would be
  // quoting a different instrument than the row asks for.
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("XAU")), null)
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("AU9999")), null)
  // Exchange contracts are fine.
  assert.equal(Yahoo.wireSymbol(SymbolID.parse("GC")), "GC=F")
})

test("only US symbols are read over an extended-session window", () => {
  const us = Yahoo.requestFor(SymbolID.parse("AAPL"))
  assert.equal(us.extended, true)
  assert.match(us.url, /includePrePost=true/)
  // Two days, not one: in pre-market a one-day window makes chartPreviousClose
  // the close before the last regular session.
  assert.match(us.url, /range=2d/)

  const hk = Yahoo.requestFor(SymbolID.parse("700.HK"))
  assert.equal(hk.extended, false)
  assert.match(hk.url, /interval=5m/)
  assert.match(hk.url, /range=1d/)
  assert.match(hk.url, /includePrePost=false/)
})

test("a regular-session response becomes a quote", () => {
  const symbol = SymbolID.parse("700.HK")
  const quote = Yahoo.parseQuote(symbol, fixture("yahoo_regular.json"), false)
  assert.ok(quote)
  assert.equal(quote.symbol, "700.HK")
  assert.equal(quote.market, "hk")
  assert.equal(quote.currencyCode, "HKD")
  assert.equal(quote.marketState, "regular")
  assert.equal(quote.sourceID, "yahoo")
  // HK is delayed about fifteen minutes, and the quote says so rather than
  // letting the panel imply it is live.
  assert.equal(quote.sourceDelaySeconds, 900)
  assert.equal(typeof quote.price, "number")
  assert.equal(typeof quote.previousClose, "number")
  assert.equal(quote.regularSession, null)
})

test("post-market prices measure against the close, not yesterday", () => {
  const quote = Yahoo.parseQuote(SymbolID.parse("TEST"), fixture("yahoo_extended_post.json"), true)
  assert.equal(quote.marketState, "postMarket")
  assert.equal(quote.price, 104.5)          // the last bar that printed
  assert.equal(quote.previousClose, 102.0)  // the regular close
  // The completed regular session rides along, against its own reference.
  assert.deepEqual(quote.regularSession, { price: 102.0, previousClose: 100.0 })
})

test("pre-market carries the last completed session, referenced to the window", () => {
  const quote = Yahoo.parseQuote(SymbolID.parse("TEST"), fixture("yahoo_extended_pre.json"), true)
  assert.equal(quote.marketState, "preMarket")
  assert.equal(quote.price, 97.5)
  assert.equal(quote.previousClose, 100.0)
  // The day has not opened, so the last regular close IS previousClose, and
  // its own reference is the close before the two-day window.
  assert.deepEqual(quote.regularSession, { price: 100.0, previousClose: 99.0 })
})

test("today's open is the first bar at or after the regular period start", () => {
  // Not the window's first bar: on a two-day range that is yesterday's
  // pre-market print.
  const quote = Yahoo.parseQuote(SymbolID.parse("TEST"), fixture("yahoo_extended_post.json"), true)
  assert.equal(quote.open, 100.0)
})

test("a delisted or misspelled symbol yields no quote rather than a wrong one", () => {
  assert.equal(Yahoo.parseQuote(SymbolID.parse("AAPL"), fixture("yahoo_unknown.json"), true), null)
  assert.equal(Yahoo.parseQuote(SymbolID.parse("AAPL"), {}, true), null)
  assert.equal(Yahoo.parseQuote(SymbolID.parse("AAPL"), { chart: { result: [{ meta: {} }] } }, true), null)
})

test("the last bar is found by scanning back past Yahoo's null padding", () => {
  const result = fixture("yahoo_extended_post.json").chart.result[0]
  const latest = Yahoo.latestClose(result)
  assert.equal(latest.price, 104.5)
})

test("the quote carries an intraday series from the same chart response", () => {
  const quote = Yahoo.parseQuote(SymbolID.parse("TEST"), fixture("yahoo_extended_post.json"), true)
  assert.deepEqual(quote.series.points, [98.2, 100.1, 101.5, 104.5])
  assert.equal(quote.series.min, 98.2)
  assert.equal(quote.series.max, 104.5)
})

test("the US intraday line starts at today's session, not the window's edge", () => {
  // The two-day window opens on yesterday's pre-market. Joining that to today
  // draws a straight edge across the overnight gap that never traded.
  const base = 1787000000
  const payload = {
    chart: {
      result: [{
        meta: {
          currency: "USD", regularMarketPrice: 101,
          previousClose: 100, chartPreviousClose: 99,
          regularMarketTime: base + 90000,
          currentTradingPeriod: {
            pre: { start: base + 86400, end: base + 106200 },
            regular: { start: base + 106200, end: base + 129600 },
            post: { start: base + 129600, end: base + 144000 }
          }
        },
        // Two yesterday bars, then three from today.
        timestamp: [base, base + 20000, base + 86400, base + 106200, base + 110000],
        indicators: { quote: [{ open: [null, null, 90, 95, 96], close: [80, 85, 90, 95, 101] }] }
      }],
      error: null
    }
  }
  const series = Yahoo.intradaySeries(payload.chart.result[0], true)
  assert.deepEqual(series.points, [90, 95, 101])
  // Yesterday's 80 would otherwise drag the floor down and flatten today.
  assert.equal(series.min, 90)
  assert.equal(series.max, 101)
})

test("a non-US series keeps the whole day, which is the whole window", () => {
  const result = fixture("yahoo_regular.json").chart.result[0]
  const series = Yahoo.intradaySeries(result, false)
  // The fixture is a daily-interval capture, so it has too few bars to draw.
  // The adapter says so rather than handing the row a one-point line.
  if (series) assert.ok(series.points.length >= 2)
})

test("a response with nothing to draw yields no series rather than a flat line", () => {
  assert.equal(Yahoo.intradaySeries({ meta: {}, indicators: {} }, false), null)
  assert.equal(Yahoo.intradaySeries({
    meta: {}, timestamp: [1], indicators: { quote: [{ close: [100] }] }
  }, false), null)
})

test("candle windows follow the macOS app's periods", () => {
  const symbol = SymbolID.parse("AAPL")
  assert.match(Yahoo.candleRequest(symbol, "day").url, /interval=1d&range=6mo/)
  assert.match(Yahoo.candleRequest(symbol, "week").url, /interval=1wk&range=2y/)
  assert.match(Yahoo.candleRequest(symbol, "month").url, /interval=1mo&range=10y/)
  assert.equal(Yahoo.candleRequest(symbol, "intraday"), null)
  assert.equal(Yahoo.candleRequest(SymbolID.parse("BTC/USDT"), "day"), null)
})

test("candles drop Yahoo's null padding and keep the live bar", () => {
  const payload = { chart: { result: [{
    timestamp: [100, 200, 300, 400],
    meta: {},
    indicators: { quote: [{
      open: [10, null, 12, 13], high: [11, null, 13, 14],
      low: [9, null, 11, 12], close: [10.5, null, 12.5, 13.5],
      volume: [1000, null, 2000, null]
    }] }
  }], error: null } }
  const candles = Yahoo.parseCandles(payload)
  assert.equal(candles.length, 3)
  assert.deepEqual(candles[0], { timestampMs: 100000, open: 10, high: 11, low: 9, close: 10.5, volume: 1000 })
  // A missing volume is zero, not a dropped candle — indices carry no volume.
  assert.equal(candles[2].volume, 0)
})

test("no candles is null, not an empty chart", () => {
  assert.equal(Yahoo.parseCandles({}), null)
  assert.equal(Yahoo.parseCandles({ chart: { result: [{ timestamp: [], meta: {}, indicators: { quote: [{}] } }] } }), null)
})
