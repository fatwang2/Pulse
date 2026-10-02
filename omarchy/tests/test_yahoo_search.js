const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const { load } = require("./qmljs.js")

const Yahoo = load("YahooAdapter.js")
const SymbolID = load("SymbolID.js")

function fixture(name) {
  return JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8"))
}

test("a wire symbol turns back into the identity it came from", () => {
  const cases = [
    ["AAPL", "AAPL"], ["0700.HK", "700.HK"], ["600519.SS", "600519.SH"],
    ["300750.SZ", "300750.SZ"], ["7203.T", "7203.T"],
    ["005930.KS", "005930.KS"], ["035720.KQ", "035720.KQ"],
    ["^GSPC", "SPX"], ["^HSI", "HSI.HK"], ["GC=F", "GC"]
  ]
  for (const [wire, canonical] of cases) {
    assert.equal(SymbolID.toString(Yahoo.symbolFromWire(wire)), canonical, wire)
  }
})

test("wire mapping round trips", () => {
  for (const raw of ["AAPL", "700.HK", "600519.SH", "7203.T", "005930.KS", "SPX", "GC"]) {
    const symbol = SymbolID.parse(raw)
    assert.equal(SymbolID.toString(Yahoo.symbolFromWire(Yahoo.wireSymbol(symbol))), raw, raw)
  }
})

test("markets Pulse does not model are refused, not guessed at", () => {
  // Guessing US would put a Frankfurt listing on the watchlist under a US badge.
  for (const wire of ["BMW.DE", "9TO.F", "0R2V.L", "EURUSD=X", "CL=F", ""]) {
    assert.equal(Yahoo.symbolFromWire(wire), null, wire)
  }
})

test("Yahoo's crypto spelling is refused; a share class is not", () => {
  // Binance is the sole source of truth for pairs, so BTC-USD must not become
  // a US ticker this adapter can never price.
  assert.equal(Yahoo.symbolFromWire("BTC-USD"), null)
  assert.equal(Yahoo.symbolFromWire("ETH-USDT"), null)
  assert.equal(Yahoo.looksLikeCryptoPair("BTC-USD"), true)
  // A hyphen alone does not mean crypto.
  assert.equal(Yahoo.looksLikeCryptoPair("BRK-B"), false)
  assert.equal(SymbolID.toString(Yahoo.symbolFromWire("BRK-B")), "BRK-B")
})

test("an empty query asks nothing", () => {
  assert.equal(Yahoo.searchRequest(""), null)
  assert.equal(Yahoo.searchRequest("   "), null)
  assert.match(Yahoo.searchRequest("toyota").url, /q=toyota/)
  assert.match(Yahoo.searchRequest("a b&c").url, /q=a%20b%26c/)
})

test("search results become watchlist-ready identities", () => {
  const results = Yahoo.parseSearch(fixture("yahoo_search.json"))
  const keys = results.map(r => r.key)
  assert.ok(keys.indexOf("TM") >= 0)
  assert.ok(keys.indexOf("7203.T") >= 0)
  // Frankfurt and every other unmodelled venue drop out rather than arriving
  // as a row that can never quote.
  assert.equal(keys.indexOf("9TO.F"), -1)
  for (const result of results) {
    assert.equal(SymbolID.toString(SymbolID.parse(result.key)), result.key)
    assert.ok(result.name && result.market && result.type)
  }
})

test("only instrument types that can become a row survive", () => {
  const payload = {
    quotes: [
      { symbol: "AAPL", quoteType: "EQUITY", longname: "Apple" },
      { symbol: "GLD", quoteType: "ETF", longname: "SPDR Gold" },
      { symbol: "^GSPC", quoteType: "INDEX", longname: "S&P 500" },
      { symbol: "USDJPY=X", quoteType: "CURRENCY", longname: "USD/JPY" },
      { symbol: "AAPL260116C00200000", quoteType: "OPTION", longname: "Call" },
      { symbol: "BTC-USD", quoteType: "CRYPTOCURRENCY", longname: "Bitcoin" }
    ]
  }
  assert.deepEqual(Yahoo.parseSearch(payload).map(r => r.key), ["AAPL", "GLD", "SPX"])
})

test("one instrument appears once, however many spellings Yahoo returns", () => {
  const payload = {
    quotes: [
      { symbol: "AAPL", quoteType: "EQUITY", longname: "Apple Inc." },
      { symbol: "AAPL", quoteType: "EQUITY", shortname: "Apple" }
    ]
  }
  assert.equal(Yahoo.parseSearch(payload).length, 1)
})

test("a malformed or empty search payload yields no results, not a throw", () => {
  assert.deepEqual(Yahoo.parseSearch({}), [])
  assert.deepEqual(Yahoo.parseSearch({ quotes: [] }), [])
  assert.deepEqual(Yahoo.parseSearch(null), [])
  assert.deepEqual(Yahoo.parseSearch({ quotes: [{}, { symbol: null }] }), [])
})

test("a code that names its venue resolves without the index", () => {
  // Yahoo cannot find 600519.SH — that spelling is Pulse's, not its own — and
  // answers 400 to Chinese text outright, so the fallback users are pointed at
  // has to work locally or the advice is wrong.
  for (const [query, key] of [
    ["600519.SH", "600519.SH"], ["600519.SS", "600519.SH"], ["7203.T", "7203.T"],
    ["00700.HK", "700.HK"], ["035720.KQ", "035720.KQ"], ["^GSPC", "SPX"]
  ]) {
    const direct = Yahoo.directMatch(query)
    assert.ok(direct, query)
    assert.equal(direct.key, key, query)
  }
})

test("a bare US ticker is left to the index, because a word looks the same", () => {
  // `nvidia` parses as a valid ten-character US code; offering it as a symbol
  // would put a row on the list that can never quote.
  for (const query of ["nvidia", "toyota", "AAPL", "BRK-B", ""]) {
    assert.equal(Yahoo.directMatch(query), null, query)
  }
})

test("an instrument this provider cannot price is not offered", () => {
  // Binance owns pairs and no Yahoo spot metal symbol works.
  assert.equal(Yahoo.directMatch("BTC/USDT"), null)
  assert.equal(Yahoo.directMatch("XAU"), null)
  assert.equal(Yahoo.directMatch("AU9999"), null)
})

test("the typed code leads, and takes the index's name when there is one", () => {
  const payload = {
    quotes: [{ symbol: "7203.T", quoteType: "EQUITY", longname: "Toyota Motor Corporation", exchDisp: "Tokyo Stock Exchange" }]
  }
  const results = Yahoo.parseSearch(payload, "7203.T")
  assert.equal(results.length, 1, "the same instrument must not appear twice")
  assert.equal(results[0].key, "7203.T")
  assert.equal(results[0].name, "Toyota Motor Corporation")
  assert.equal(results[0].exchangeName, "Tokyo Stock Exchange")
})

test("with no index response at all, the typed code is still an answer", () => {
  const results = Yahoo.parseSearch(null, "600519.SH")
  assert.deepEqual(results.map(r => r.key), ["600519.SH"])
  assert.equal(results[0].name, null)
  assert.deepEqual(Yahoo.parseSearch(null, "nvidia"), [])
})
