// Panel state. Every function here is pure: the panel hands the current state
// and an event in, and gets the next state back. That keeps the reducer
// testable under `node --test`, where none of the Quickshell types exist.

.import "SymbolID.js" as SymbolID
.import "Market.js" as Market

var STALE_AFTER_MS = 5 * 60 * 1000

function initialState() {
  return {
    symbols: [],      // canonical symbol strings, in watchlist order
    quotes: {},       // canonical symbol -> quote
    errors: {},       // canonical symbol -> last error message
    updatedMs: 0
  }
}

// Watchlist membership. Unparseable entries are dropped rather than kept as
// dead rows, and duplicates collapse to the first occurrence so the file can be
// hand-edited without producing two rows for one instrument.
function applySymbols(state, rawSymbols) {
  var source = (rawSymbols && typeof rawSymbols.length === "number") ? rawSymbols : []
  var seen = {}
  var symbols = []
  for (var i = 0; i < source.length; i++) {
    var parsed = SymbolID.parse(source[i])
    if (!parsed) continue
    var key = SymbolID.toString(parsed)
    if (seen[key]) continue
    seen[key] = true
    symbols.push(key)
  }

  // Quotes for symbols that left the watchlist are dropped with them; a row
  // that comes back should refetch rather than paint a stale price.
  var quotes = {}
  var errors = {}
  for (var j = 0; j < symbols.length; j++) {
    if (state.quotes[symbols[j]]) quotes[symbols[j]] = state.quotes[symbols[j]]
    if (state.errors[symbols[j]]) errors[symbols[j]] = state.errors[symbols[j]]
  }

  return { symbols: symbols, quotes: quotes, errors: errors, updatedMs: state.updatedMs }
}

// A quote landing. The symbol must still be on the watchlist — a response can
// outlive the row that asked for it.
function applyQuote(state, quote) {
  if (!quote || !quote.symbol) return state
  if (state.symbols.indexOf(quote.symbol) < 0) return state
  var quotes = {}
  for (var key in state.quotes) {
    if (Object.prototype.hasOwnProperty.call(state.quotes, key)) quotes[key] = state.quotes[key]
  }
  quotes[quote.symbol] = quote
  var errors = {}
  for (var errKey in state.errors) {
    if (Object.prototype.hasOwnProperty.call(state.errors, errKey) && errKey !== quote.symbol) {
      errors[errKey] = state.errors[errKey]
    }
  }
  return { symbols: state.symbols, quotes: quotes, errors: errors, updatedMs: quote.timestampMs || state.updatedMs }
}

function applyError(state, symbol, message) {
  if (!symbol || state.symbols.indexOf(symbol) < 0) return state
  var errors = {}
  for (var key in state.errors) {
    if (Object.prototype.hasOwnProperty.call(state.errors, key)) errors[key] = state.errors[key]
  }
  errors[symbol] = String(message || "unavailable")
  return { symbols: state.symbols, quotes: state.quotes, errors: errors, updatedMs: state.updatedMs }
}

// --- Derived values -------------------------------------------------------

function change(quote) {
  if (!quote) return null
  return quote.price - quote.previousClose
}

function changePercent(quote) {
  if (!quote || !quote.previousClose) return null
  return (quote.price - quote.previousClose) / quote.previousClose * 100
}

// Today's high-low range against the previous close. Provider-independent,
// because every quote source carries all three inputs.
function amplitudePercent(quote) {
  if (!quote) return null
  if (typeof quote.high !== "number" || typeof quote.low !== "number") return null
  if (!(quote.previousClose > 0) || quote.high < quote.low) return null
  return (quote.high - quote.low) / quote.previousClose * 100
}

function regularSessionChangePercent(quote) {
  var session = quote && quote.regularSession
  if (!session || !session.previousClose) return null
  return (session.price - session.previousClose) / session.previousClose * 100
}

// How old a price may get before the panel stops vouching for it. A source
// that is delayed fifteen minutes can never produce a timestamp fresher than
// fifteen minutes, so measuring it against a five-minute bar would mark it
// stale permanently and say nothing.
function stalenessThresholdMs(quote) {
  var delay = (quote && typeof quote.sourceDelaySeconds === "number" && quote.sourceDelaySeconds > 0)
    ? quote.sourceDelaySeconds * 1000
    : 0
  return STALE_AFTER_MS + delay
}

function isStale(quote, nowMs) {
  if (!quote || !quote.timestampMs) return true
  // A closed market's last print is the close: final, not stale. Without this,
  // every Asian row carries a warning through the whole European and American
  // day, which teaches the eye to skip the marker on the one row where it
  // means something.
  if (!Market.isOpen(quote.market, nowMs)) return false
  return (Number(nowMs) - quote.timestampMs) > stalenessThresholdMs(quote)
}

// --- Rows -----------------------------------------------------------------

// Rows keep the list's own order, verbatim. The list is the user's ranking —
// the macOS app lets it be dragged into shape — and "move up" in the detail
// view edits the same order the rows display, so the button's effect is the
// effect you see. Nothing here sorts at all, least of all on a value that
// moves.
//
// The key list is a parameter because the state quotes every symbol on every
// list, while a tab shows only its own. Quotes for the other tabs stay warm in
// the state, so switching tabs paints prices instead of an empty list.
function rowsForSymbols(state, symbolKeys) {
  var buckets = []
  var source = (symbolKeys && typeof symbolKeys.length === "number") ? symbolKeys : []
  for (var i = 0; i < source.length; i++) {
    var key = source[i]
    var parsed = SymbolID.parse(key)
    if (!parsed) continue
    var quote = state.quotes[key] || null
    buckets.push({
      key: key,
      symbol: parsed,
      displayCode: SymbolID.displayCode(parsed),
      market: parsed.market,
      marketLabel: Market.displayLabel(parsed.market),
      name: (quote && quote.name) || null,
      quote: quote,
      error: state.errors[key] || null,
      change: change(quote),
      changePercent: changePercent(quote),
      amplitudePercent: amplitudePercent(quote),
      regularChangePercent: regularSessionChangePercent(quote),
      order: i
    })
  }
  return buckets
}

function rows(state) {
  return rowsForSymbols(state, state.symbols)
}

// --- Formatting -----------------------------------------------------------

// Precision follows magnitude rather than market: a 3900-point index and a
// 0.42 penny stock both need to read as a price, and a fixed 2 decimals fails
// one end or the other.
function formatPrice(value) {
  if (typeof value !== "number" || !isFinite(value)) return "—"
  var magnitude = Math.abs(value)
  var digits = magnitude >= 1 ? 2 : (magnitude >= 0.01 ? 4 : 6)
  var text = value.toFixed(digits)
  var dot = text.indexOf(".")
  var whole = dot < 0 ? text : text.slice(0, dot)
  var fraction = dot < 0 ? "" : text.slice(dot)
  // Group the integer part only; thousands separators inside the decimals
  // would turn 3903.721 into something that is not a number.
  var sign = whole.charAt(0) === "-" ? "-" : ""
  if (sign) whole = whole.slice(1)
  return sign + whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + fraction
}

function formatPercent(value) {
  if (typeof value !== "number" || !isFinite(value)) return "—"
  return (value >= 0 ? "+" : "") + value.toFixed(2) + "%"
}

function formatChange(value) {
  if (typeof value !== "number" || !isFinite(value)) return "—"
  return (value >= 0 ? "+" : "") + formatPrice(value)
}

// Volume reads as a magnitude, not a count: nobody parses 7032418 at a glance.
function formatVolume(value) {
  if (typeof value !== "number" || !isFinite(value)) return "—"
  var abs = Math.abs(value)
  if (abs >= 1e12) return (value / 1e12).toFixed(2) + "T"
  if (abs >= 1e9) return (value / 1e9).toFixed(2) + "B"
  if (abs >= 1e6) return (value / 1e6).toFixed(2) + "M"
  if (abs >= 1e3) return (value / 1e3).toFixed(2) + "K"
  return String(Math.round(value))
}

var SESSION_LABELS = {
  preMarket: "PRE",
  regular: "",
  postMarket: "POST",
  overnight: "OVERNIGHT",
  closed: "CLOSED"
}

function sessionLabel(quote) {
  if (!quote || !quote.marketState) return ""
  return SESSION_LABELS[quote.marketState] === undefined ? "" : SESSION_LABELS[quote.marketState]
}

if (typeof module !== "undefined") module.exports = {
  STALE_AFTER_MS: STALE_AFTER_MS,
  initialState: initialState,
  applySymbols: applySymbols,
  applyQuote: applyQuote,
  applyError: applyError,
  change: change,
  changePercent: changePercent,
  amplitudePercent: amplitudePercent,
  regularSessionChangePercent: regularSessionChangePercent,
  stalenessThresholdMs: stalenessThresholdMs,
  isStale: isStale,
  rows: rows,
  rowsForSymbols: rowsForSymbols,
  formatPrice: formatPrice,
  formatPercent: formatPercent,
  formatChange: formatChange,
  formatVolume: formatVolume,
  sessionLabel: sessionLabel
}
