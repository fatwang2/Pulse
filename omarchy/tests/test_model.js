const test = require("node:test")
const assert = require("node:assert/strict")

const { load } = require("./qmljs.js")

const Model = load("Model.js")

function quote(symbol, overrides) {
  return Object.assign({
    symbol: symbol, price: 100, previousClose: 100, name: "Test",
    timestampMs: 1787000000000, marketState: "regular"
  }, overrides || {})
}

test("the watchlist drops what can never quote and collapses duplicates", () => {
  const state = Model.applySymbols(Model.initialState(),
    [" aapl ", "00700.HK", "AAPL", "garbage!!", "600519.SH", ""])
  assert.deepEqual(state.symbols, ["AAPL", "700.HK", "600519.SH"])
})

test("a symbol leaving the watchlist takes its price with it", () => {
  let state = Model.applySymbols(Model.initialState(), ["AAPL", "NVDA"])
  state = Model.applyQuote(state, quote("AAPL"))
  state = Model.applyQuote(state, quote("NVDA"))
  state = Model.applySymbols(state, ["AAPL"])
  assert.deepEqual(Object.keys(state.quotes), ["AAPL"])
})

test("a response that outlives its row is discarded", () => {
  const state = Model.applySymbols(Model.initialState(), ["AAPL"])
  assert.equal(Model.applyQuote(state, quote("NVDA")), state)
})

test("a landing quote clears the row's error", () => {
  let state = Model.applySymbols(Model.initialState(), ["AAPL"])
  state = Model.applyError(state, "AAPL", "rate limited")
  assert.equal(state.errors.AAPL, "rate limited")
  state = Model.applyQuote(state, quote("AAPL"))
  assert.equal(state.errors.AAPL, undefined)
})

test("derived figures come from price and previous close, never from the source", () => {
  const q = quote("AAPL", { price: 105, previousClose: 100, high: 106, low: 99 })
  assert.equal(Model.change(q), 5)
  assert.equal(Model.changePercent(q), 5)
  assert.ok(Math.abs(Model.amplitudePercent(q) - 7) < 1e-9)
  // A zero previous close would divide by zero; it yields nothing instead.
  assert.equal(Model.changePercent(quote("AAPL", { previousClose: 0 })), null)
  assert.equal(Model.amplitudePercent(quote("AAPL", { high: 1 })), null)
})

test("rows keep the list's own order verbatim", () => {
  // The list is the user's ranking. "Move up" edits the same order the rows
  // display, so nothing may re-sort it — not even by market.
  let state = Model.applySymbols(Model.initialState(),
    ["700.HK", "NVDA", "600519.SH", "AAPL", "7203.T"])
  assert.deepEqual(Model.rows(state).map(r => r.key),
    ["700.HK", "NVDA", "600519.SH", "AAPL", "7203.T"])
})

test("row order does not move when a price does", () => {
  let state = Model.applySymbols(Model.initialState(), ["AAPL", "NVDA"])
  const before = Model.rows(state).map(r => r.key)
  state = Model.applyQuote(state, quote("NVDA", { price: 500, previousClose: 100 }))
  assert.deepEqual(Model.rows(state).map(r => r.key), before)
})

test("both Chinese boards and both Korean boards share one badge", () => {
  const state = Model.applySymbols(Model.initialState(),
    ["600519.SH", "300750.SZ", "005930.KS", "035720.KQ"])
  assert.deepEqual(Model.rows(state).map(r => r.marketLabel), ["CN", "CN", "KR", "KR"])
})

test("a tab draws its own symbols with quotes kept warm for every tab", () => {
  // The state subscribes to the union of all lists; a tab renders its subset.
  let state = Model.applySymbols(Model.initialState(), ["AAPL", "NVDA", "700.HK"])
  state = Model.applyQuote(state, quote("700.HK", { name: "Tencent Holdings" }))
  const rows = Model.rowsForSymbols(state, ["700.HK", "NVDA"])
  assert.deepEqual(rows.map(r => r.key), ["700.HK", "NVDA"])
  assert.equal(rows[0].name, "Tencent Holdings")
  // A key the state no longer quotes still rows up (as an empty row), and an
  // empty tab is an empty list, not an error.
  assert.deepEqual(Model.rowsForSymbols(state, []), [])
})

test("a quote stops being trusted after five minutes, while its market is open", () => {
  // Crypto is the one market that is always open, so it isolates the age rule.
  const q = quote("BTC/USDT", { market: "crypto", timestampMs: 1787000000000 })
  assert.equal(Model.isStale(q, 1787000000000 + 60000), false)
  assert.equal(Model.isStale(q, 1787000000000 + 6 * 60000), true)
  // A row that has never quoted is stale by definition.
  assert.equal(Model.isStale(null, Date.now()), true)
})

test("a closed market's last print is the close, not a stale price", () => {
  // Tokyo, long shut: the price is hours old and entirely correct.
  const closed = Date.UTC(2026, 7, 20, 12, 0) // 21:00 JST
  const q = quote("7203.T", { market: "jp", timestampMs: Date.UTC(2026, 7, 20, 6, 0) })
  assert.equal(Model.isStale(q, closed), false)
})

test("a delayed source is not marked stale for being delayed", () => {
  // Hong Kong through Yahoo is fifteen minutes behind by design, so its
  // freshest possible timestamp is already older than the base threshold.
  const open = Date.UTC(2026, 7, 20, 2, 0) // 10:00 HKT, mid-session
  const delayed = quote("700.HK", {
    market: "hk", sourceDelaySeconds: 900, timestampMs: open - 10 * 60000
  })
  assert.equal(Model.isStale(delayed, open), false)
  assert.equal(Model.stalenessThresholdMs(delayed), Model.STALE_AFTER_MS + 900000)
  // Past the delay plus the threshold it is genuinely not arriving.
  assert.equal(Model.isStale(delayed, open + 15 * 60000), true)
})

test("precision follows magnitude, because a fixed one fails an end", () => {
  assert.equal(Model.formatPrice(3903.721), "3,903.72")
  assert.equal(Model.formatPrice(316.9), "316.90")
  assert.equal(Model.formatPrice(0.4231), "0.4231")
  assert.equal(Model.formatPrice(0.00012345), "0.000123")
  assert.equal(Model.formatPrice(-1234567.891), "-1,234,567.89")
  // Grouping must never reach the decimals.
  assert.equal(Model.formatPrice(1234.5678), "1,234.57")
  assert.equal(Model.formatPrice(null), "—")
})

test("percent and change always carry their sign", () => {
  assert.equal(Model.formatPercent(2.5), "+2.50%")
  assert.equal(Model.formatPercent(-2.17), "-2.17%")
  assert.equal(Model.formatPercent(0), "+0.00%")
  assert.equal(Model.formatChange(4.2), "+4.20")
})

test("volume reads as a magnitude, not a count", () => {
  assert.equal(Model.formatVolume(7032418), "7.03M")
  assert.equal(Model.formatVolume(3418755144), "3.42B")
  assert.equal(Model.formatVolume(4210), "4.21K")
  assert.equal(Model.formatVolume(42), "42")
})

test("only an extended session is labelled; regular is the default state", () => {
  assert.equal(Model.sessionLabel(quote("AAPL", { marketState: "regular" })), "")
  assert.equal(Model.sessionLabel(quote("AAPL", { marketState: "preMarket" })), "PRE")
  assert.equal(Model.sessionLabel(quote("AAPL", { marketState: "postMarket" })), "POST")
  assert.equal(Model.sessionLabel(quote("AAPL", { marketState: "closed" })), "CLOSED")
})

test("the regular session's own change is measured against its own reference", () => {
  const q = quote("AAPL", {
    price: 104.5, previousClose: 102,
    regularSession: { price: 102, previousClose: 100 }
  })
  assert.equal(Model.regularSessionChangePercent(q), 2)
  assert.equal(Model.regularSessionChangePercent(quote("AAPL")), null)
})
