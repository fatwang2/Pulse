// Provider-independent instrument identity, ported from PulseCore's
// `SymbolID.swift`.
//
// Stocks and ETFs can use their exchange ticker directly. Indices cannot —
// `sp500` is `^GSPC` at Yahoo, `INX` at Tencent and `.SPX.US` at Longbridge —
// so they carry a semantic id and every adapter maps it to its own wire form.
// Metals do the same, and crypto is a structured base/quote pair rather than a
// ticker, because `BTCUSDT` is Binance's spelling, not the instrument's name.

.import "Market.js" as Market

var KIND_SECURITY = "security"
var KIND_INDEX = "index"
var KIND_METAL = "metal"
var KIND_CRYPTO = "crypto"

// Semantic index identities and the market each belongs to.
var INDEXES = {
  sp500:               { market: "us", code: "SPX" },
  nasdaqComposite:     { market: "us", code: "IXIC" },
  dowJonesIndustrial:  { market: "us", code: "DJI" },
  nasdaq100:           { market: "us", code: "NDX" },
  vix:                 { market: "us", code: "VIX" },
  russell1000:         { market: "us", code: "RUI" },
  russell2000:         { market: "us", code: "RUT" },
  hangSeng:            { market: "hk", code: "HSI" },
  hangSengTech:        { market: "hk", code: "HSTECH" },
  shanghaiComposite:   { market: "sh", code: "000001" },
  shenzhenComponent:   { market: "sz", code: "399001" },
  chiNext:             { market: "sz", code: "399006" },
  nikkei225:           { market: "jp", code: "N225" },
  kospi:               { market: "kr", code: "KOSPI" }
}

// Metal identities. `spot` instruments are the ones a person means by "gold";
// the rest are exchange contracts. Yahoo carries no working spot symbol, which
// is why the spot rows need a different source than the futures rows.
var METALS = {
  goldSpot:         { market: "metal",   code: "XAU",    spot: true },
  gold:             { market: "metal",   code: "GC",     spot: false },
  silverSpot:       { market: "metal",   code: "XAG",    spot: true },
  silver:           { market: "metal",   code: "SI",     spot: false },
  platinum:         { market: "metal",   code: "PL",     spot: false },
  palladium:        { market: "metal",   code: "PA",     spot: false },
  shanghaiGoldSpot: { market: "metalCN", code: "AU9999", spot: true },
  shanghaiGold:     { market: "metalCN", code: "AUM",    spot: false },
  shanghaiSilver:   { market: "metalCN", code: "AGM",    spot: false }
}

function trimmed(value) {
  return String(value === null || value === undefined ? "" : value).replace(/^\s+|\s+$/g, "")
}

// Vendor spellings of the same index. Pulse accepts them because they are what
// a person copies out of another terminal: `GSPC` is Yahoo's, `INX` is
// Tencent's, and `NKY` is Bloomberg's, but all three name one benchmark.
var INDEX_ALIASES = {
  sp500:              ["SPX", "GSPC", "INX"],
  nasdaqComposite:    ["IXIC", "COMP"],
  dowJonesIndustrial: ["DJI"],
  nasdaq100:          ["NDX"],
  vix:                ["VIX"],
  russell1000:        ["RUI"],
  russell2000:        ["RUT"],
  hangSeng:           ["HSI"],
  hangSengTech:       ["HSTECH"],
  shanghaiComposite:  ["000001"],
  shenzhenComponent:  ["399001"],
  chiNext:            ["399006"],
  nikkei225:          ["N225", "NKY"],
  kospi:              ["KOSPI", "KS11"]
}

// A market suffix already consumed by `parse` may still be present when a code
// is handed in directly ("SPX.US"), so it is stripped here too.
function bareIndexCode(code) {
  return String(code || "")
    .replace(/^\s+|\s+$/g, "")
    .toUpperCase()
    .replace(/\.(US|HK|SH|SS|SZ|T|KS|KQ)$/, "")
    .replace(/^[\^.]/, "")
}

function indexIDFor(market, code) {
  var upper = bareIndexCode(code)
  if (!upper) return null
  for (var key in INDEX_ALIASES) {
    if (!Object.prototype.hasOwnProperty.call(INDEX_ALIASES, key)) continue
    if (INDEX_ALIASES[key].indexOf(upper) < 0) continue
    // A bare numeric code is an index only in the market that owns it:
    // `000001` is the Shanghai Composite on the SSE and Ping An Bank on the
    // SZSE, and the two must not collide.
    if (/^\d+$/.test(upper) && INDEXES[key].market !== market) continue
    return key
  }
  return null
}

function metalIDFor(code) {
  var upper = trimmed(code).toUpperCase().replace(/=F$/, "")
  for (var key in METALS) {
    if (Object.prototype.hasOwnProperty.call(METALS, key) && METALS[key].code === upper) return key
  }
  return null
}

function parseCryptoPair(raw) {
  var normalized = trimmed(raw).toUpperCase()
  var separator = normalized.indexOf("/") >= 0 ? "/" : "-"
  var parts = normalized.split(separator).filter(function (part) { return part.length > 0 })
  if (parts.length !== 2) return null
  return { baseAsset: parts[0], quoteAsset: parts[1] }
}

// Per-market shape of a valid security code. Pulse itself does not need this:
// every symbol there arrives from a provider's search index, already known to
// exist. Here the watchlist is a file a person edits by hand, so a typo has to
// be refused at the door rather than becoming a row that can never quote.
var CODE_PATTERNS = {
  us: /^[A-Z][A-Z0-9.\-]{0,9}$/,
  hk: /^[0-9A-Z]{1,6}$/,
  sh: /^\d{6}$/,
  sz: /^\d{6}$/,
  // Tokyo codes are four characters and, since 2024, may end in a letter (130A).
  jp: /^[0-9][0-9A-Z]{3}$/,
  kr: /^\d{6}$/,
  kq: /^\d{6}$/,
  metal: /^[A-Z0-9]{1,8}$/,
  metalCN: /^[A-Z0-9]{1,8}$/
}

function isValidSecurityCode(code, market) {
  var pattern = CODE_PATTERNS[market]
  return !!pattern && pattern.test(code)
}

// HK codes are stored unpadded ("00700" -> "700") so that one symbol has one
// identity; each adapter re-pads to the width it wants.
function normalizeSecurityCode(code, market) {
  var value = trimmed(code)
  if (market === "hk") {
    return /^\d+$/.test(value) ? String(parseInt(value, 10)) : value.toUpperCase()
  }
  return value.toUpperCase()
}

// The one constructor. Everything else in the plugin builds symbols through
// it, so an index or a metal typed by hand resolves to the same identity the
// catalog would have produced.
function create(market, code) {
  var normalizedMarket = trimmed(market).toLowerCase()
  if (!Market.isKnown(normalizedMarket)) return null

  if (normalizedMarket === "crypto") {
    var pair = parseCryptoPair(code)
    if (!pair) return null
    return { kind: KIND_CRYPTO, market: "crypto", pair: pair }
  }

  var metal = metalIDFor(code)
  if (metal) return { kind: KIND_METAL, market: METALS[metal].market, id: metal }

  var index = indexIDFor(normalizedMarket, code)
  if (index) return { kind: KIND_INDEX, market: INDEXES[index].market, id: index }

  var securityCode = normalizeSecurityCode(code, normalizedMarket)
  if (!isValidSecurityCode(securityCode, normalizedMarket)) return null
  return { kind: KIND_SECURITY, market: normalizedMarket, code: securityCode }
}

function code(symbol) {
  if (!symbol) return ""
  switch (symbol.kind) {
    case KIND_INDEX: return INDEXES[symbol.id].code
    case KIND_METAL: return METALS[symbol.id].code
    case KIND_CRYPTO: return symbol.pair.baseAsset + "-" + symbol.pair.quoteAsset
    default: return symbol.code
  }
}

function displayCode(symbol) {
  if (symbol && symbol.kind === KIND_CRYPTO) {
    return symbol.pair.baseAsset + "/" + symbol.pair.quoteAsset
  }
  return code(symbol)
}

// The canonical text form, and the key the panel stores state under. It round
// trips through `parse`.
function toString(symbol) {
  if (!symbol) return ""
  var base = code(symbol)
  switch (symbol.market) {
    case "us": return base
    case "hk": return base + ".HK"
    case "sh": return base + ".SH"
    case "sz": return base + ".SZ"
    case "jp": return base + ".T"
    case "kr": return base + ".KS"
    case "kq": return base + ".KQ"
    case "crypto": return displayCode(symbol)
    default: return base
  }
}

var SUFFIX_MARKETS = { HK: "hk", SH: "sh", SS: "sh", SZ: "sz", T: "jp", KS: "kr", KQ: "kq" }

// Parses the canonical form back into an identity. A code with no suffix is a
// US ticker, which is the one market whose symbols carry no venue marker.
function parse(raw) {
  var value = trimmed(raw)
  if (!value) return null
  if (value.indexOf("/") >= 0) return create("crypto", value)

  var dot = value.lastIndexOf(".")
  if (dot > 0) {
    var suffix = value.slice(dot + 1).toUpperCase()
    if (Object.prototype.hasOwnProperty.call(SUFFIX_MARKETS, suffix)) {
      return create(SUFFIX_MARKETS[suffix], value.slice(0, dot))
    }
  }
  return create("us", value)
}

function currencyCode(symbol) {
  if (symbol && symbol.kind === KIND_CRYPTO) return symbol.pair.quoteAsset
  return Market.currencyCode(symbol ? symbol.market : "us")
}

function isIndex(symbol) { return !!symbol && symbol.kind === KIND_INDEX }
function isMetal(symbol) { return !!symbol && symbol.kind === KIND_METAL }
function isCrypto(symbol) { return !!symbol && symbol.kind === KIND_CRYPTO }
function isSpotMetal(symbol) { return isMetal(symbol) && METALS[symbol.id].spot }

function equal(a, b) {
  return !!a && !!b && a.market === b.market && a.kind === b.kind && toString(a) === toString(b)
}

if (typeof module !== "undefined") module.exports = {
  KIND_SECURITY: KIND_SECURITY,
  KIND_INDEX: KIND_INDEX,
  KIND_METAL: KIND_METAL,
  KIND_CRYPTO: KIND_CRYPTO,
  INDEXES: INDEXES,
  METALS: METALS,
  create: create,
  parse: parse,
  code: code,
  displayCode: displayCode,
  toString: toString,
  currencyCode: currencyCode,
  parseCryptoPair: parseCryptoPair,
  CODE_PATTERNS: CODE_PATTERNS,
  isValidSecurityCode: isValidSecurityCode,
  normalizeSecurityCode: normalizeSecurityCode,
  INDEX_ALIASES: INDEX_ALIASES,
  indexIDFor: indexIDFor,
  metalIDFor: metalIDFor,
  isIndex: isIndex,
  isMetal: isMetal,
  isCrypto: isCrypto,
  isSpotMetal: isSpotMetal,
  equal: equal
}
