const test = require("node:test")
const assert = require("node:assert/strict")

const { load } = require("./qmljs.js")

const SymbolID = load("SymbolID.js")

test("canonical symbols round trip through parse and toString", () => {
  const cases = ["AAPL", "BRK-B", "700.HK", "600519.SH", "300750.SZ", "7203.T", "005930.KS", "035720.KQ"]
  for (const raw of cases) {
    assert.equal(SymbolID.toString(SymbolID.parse(raw)), raw, raw)
  }
})

test("HK codes are stored unpadded so one instrument has one identity", () => {
  assert.equal(SymbolID.toString(SymbolID.parse("00700.HK")), "700.HK")
  assert.equal(SymbolID.toString(SymbolID.parse("0700.HK")), "700.HK")
  assert.equal(SymbolID.toString(SymbolID.parse("700.HK")), "700.HK")
})

test("vendor index spellings resolve to one identity", () => {
  for (const raw of ["^GSPC", "INX", "SPX", "SPX.US", ".SPX"]) {
    const symbol = SymbolID.parse(raw)
    assert.equal(symbol.kind, SymbolID.KIND_INDEX, raw)
    assert.equal(symbol.id, "sp500", raw)
  }
  assert.equal(SymbolID.parse("^COMP").id, "nasdaqComposite")
  assert.equal(SymbolID.parse("NKY").id, "nikkei225")
  assert.equal(SymbolID.parse("^KS11").id, "kospi")
})

test("a numeric index code belongs only to the market that owns it", () => {
  // 000001 is the Shanghai Composite on the SSE and Ping An Bank on the SZSE.
  assert.equal(SymbolID.parse("000001.SH").kind, SymbolID.KIND_INDEX)
  assert.equal(SymbolID.parse("000001.SH").id, "shanghaiComposite")
  assert.equal(SymbolID.parse("000001.SZ").kind, SymbolID.KIND_SECURITY)
  assert.equal(SymbolID.parse("399006.SZ").id, "chiNext")
})

test("crypto is a structured pair, not a ticker", () => {
  const btc = SymbolID.parse("BTC/USDT")
  assert.equal(btc.kind, SymbolID.KIND_CRYPTO)
  assert.deepEqual(btc.pair, { baseAsset: "BTC", quoteAsset: "USDT" })
  assert.equal(SymbolID.displayCode(btc), "BTC/USDT")
  assert.equal(SymbolID.currencyCode(btc), "USDT")
})

test("metals resolve by code and know which are spot", () => {
  assert.equal(SymbolID.parse("GC").id, "gold")
  assert.equal(SymbolID.isSpotMetal(SymbolID.parse("GC")), false)
  assert.equal(SymbolID.isSpotMetal(SymbolID.parse("XAU")), true)
  assert.equal(SymbolID.parse("AU9999").market, "metalCN")
})

test("a hand-edited watchlist cannot smuggle in a code that can never quote", () => {
  for (const raw of ["garbage!!", "12345.SH", "TOOLONGTICKER", "", "   ", "72030.T"]) {
    assert.equal(SymbolID.parse(raw), null, raw)
  }
  // Tokyo codes may end in a letter since 2024.
  assert.equal(SymbolID.parse("130A.T").kind, SymbolID.KIND_SECURITY)
})

test("currency follows the market, and the quote asset for crypto", () => {
  assert.equal(SymbolID.currencyCode(SymbolID.parse("700.HK")), "HKD")
  assert.equal(SymbolID.currencyCode(SymbolID.parse("7203.T")), "JPY")
  assert.equal(SymbolID.currencyCode(SymbolID.parse("005930.KS")), "KRW")
  assert.equal(SymbolID.currencyCode(SymbolID.parse("600519.SH")), "CNY")
})
