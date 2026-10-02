import QtQuick
import "SymbolID.js" as SymbolID
import "YahooAdapter.js" as Yahoo

// Candles for the detail chart, fetched on demand and cached per symbol and
// period. History barely moves — a daily candle changes once a session — so a
// ten-minute cache means flipping between periods or reopening a detail costs
// nothing, while the live bar still refreshes on a human timescale.
QtObject {
  id: root

  // key -> { candles, fetchedMs } ; key -> true while a request is in flight.
  property var _cache: ({})
  property var _pending: ({})
  property double _generation: 0

  readonly property int ttlMs: 10 * 60 * 1000

  function _key(symbolKey, period) {
    return symbolKey + "|" + period
  }

  // The cached candles, or null. Reading never triggers a fetch — the view
  // asks for exactly what it renders via `ensure`.
  function candlesFor(symbolKey, period) {
    void root._generation
    var entry = root._cache[root._key(symbolKey, period)]
    return entry ? entry.candles : null
  }

  function loading(symbolKey, period) {
    void root._generation
    return root._pending[root._key(symbolKey, period)] === true
  }

  function ensure(symbolKey, period) {
    var key = root._key(symbolKey, period)
    var entry = root._cache[key]
    if (entry && (Date.now() - entry.fetchedMs) < root.ttlMs) return
    if (root._pending[key]) return

    var symbol = SymbolID.parse(symbolKey)
    var spec = symbol ? Yahoo.candleRequest(symbol, period) : null
    if (!spec) return

    root._pending[key] = true
    root._generation++

    var xhr = new XMLHttpRequest()
    xhr.open("GET", spec.url)
    xhr.timeout = 10000
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) Pulse/0.1 (+https://www.pulseticker.app)")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      delete root._pending[key]
      var candles = null
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          candles = Yahoo.parseCandles(JSON.parse(xhr.responseText))
        } catch (e) {
          candles = null
        }
      }
      if (candles) {
        root._cache[key] = { candles: candles, fetchedMs: Date.now() }
      }
      // A failure leaves any stale cache in place: yesterday's history beats
      // an empty chart, and the next `ensure` past the TTL retries anyway.
      root._generation++
    }
    xhr.send()
  }
}
