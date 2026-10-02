const test = require("node:test")
const assert = require("node:assert/strict")

const { load } = require("./qmljs.js")

const SessionOrder = load("SessionOrder.js")

// 10:00 and 20:00 Beijing on 2026-08-21.
const ASIA_DAY = Date.UTC(2026, 7, 21, 2, 0)
const US_EVENING = Date.UTC(2026, 7, 21, 12, 0)

const LIST = ["AAPL", "700.HK", "600519.SH", "NVDA", "300750.SZ", "7203.T", "005930.KS", "GC", "BTC/USDT"]

test("the Beijing day leads with Asia; the evening leads with the US", () => {
  assert.equal(SessionOrder.windowAt(ASIA_DAY), "asiaDay")
  assert.equal(SessionOrder.windowAt(US_EVENING), "usEvening")
  // Boundary hours: 08:00 opens the Asian day, 17:00 closes it.
  assert.equal(SessionOrder.windowAt(Date.UTC(2026, 7, 21, 0, 0)), "asiaDay")
  assert.equal(SessionOrder.windowAt(Date.UTC(2026, 7, 21, 9, 0)), "usEvening")
})

test("daytime rebuilds into HK, China A, JP, KR, US, metals, crypto", () => {
  assert.deepEqual(SessionOrder.orderedSymbols(LIST, [], ASIA_DAY),
    ["700.HK", "600519.SH", "300750.SZ", "7203.T", "005930.KS", "AAPL", "NVDA", "GC", "BTC/USDT"])
})

test("the evening promotes only the US block; nothing else moves", () => {
  assert.deepEqual(SessionOrder.orderedSymbols(LIST, [], US_EVENING),
    ["AAPL", "NVDA", "700.HK", "600519.SH", "300750.SZ", "7203.T", "005930.KS", "GC", "BTC/USDT"])
})

test("Shanghai and Shenzhen are one block that never interleaves", () => {
  // 600519.SH ... 300750.SZ arrive with NVDA between them; the block reunites
  // them in base order.
  const day = SessionOrder.orderedSymbols(["600519.SH", "NVDA", "300750.SZ"], [], ASIA_DAY)
  assert.deepEqual(day, ["600519.SH", "300750.SZ", "NVDA"])
})

test("a pin rises to the top of its own block, not the top of the list", () => {
  const ordered = SessionOrder.orderedSymbols(LIST, ["NVDA"], ASIA_DAY)
  // NVDA leads the US block, but the US block still trails the Asian day.
  const us = ordered.slice(ordered.indexOf("NVDA"))
  assert.equal(us[0], "NVDA")
  assert.equal(us[1], "AAPL")
  assert.equal(ordered[0], "700.HK")
})

test("inside a slice the caller's sequence is untouched", () => {
  const ordered = SessionOrder.orderedSymbols(["NVDA", "AAPL", "SPX"], ["SPX"], US_EVENING)
  assert.deepEqual(ordered, ["SPX", "NVDA", "AAPL"])
})

test("an empty list is an empty list", () => {
  assert.deepEqual(SessionOrder.orderedSymbols([], [], ASIA_DAY), [])
  assert.deepEqual(SessionOrder.orderedSymbols(null, null, ASIA_DAY), [])
})

test("a fresh addition tops its market block, beneath the block's pins", () => {
  // AMD was just added (it leads the saved sequence); NVDA is pinned.
  const saved = ["AMD", "AAPL", "NVDA", "700.HK"]
  const ordered = SessionOrder.orderedSymbols(saved, ["NVDA"], US_EVENING)
  // Pins first, then the newest addition, then the rest in saved order.
  assert.deepEqual(ordered, ["NVDA", "AMD", "AAPL", "700.HK"])
})
