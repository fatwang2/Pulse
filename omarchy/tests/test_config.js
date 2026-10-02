const test = require("node:test")
const assert = require("node:assert/strict")

const { load } = require("./qmljs.js")

const Config = load("Config.js")

function roundTrip(config) {
  return Config.parse(Config.serialize(config))
}

test("an empty or missing file is a working config, not an error", () => {
  for (const raw of ["", "   ", null, undefined]) {
    const config = Config.parse(raw)
    assert.equal(config.lists.length, 1)
    assert.equal(config.activeList, config.lists[0].name)
  }
})

test("a v1 file becomes one list with the old symbols, canonicalized", () => {
  const v1 = JSON.stringify({
    version: 1,
    symbols: ["AAPL", "00700.HK", "AAPL", "garbage!!"],
    barDisplay: "carousel",
    pollIntervalSeconds: 30
  })
  const config = Config.parse(v1)
  assert.deepEqual(config.lists, [{ name: "Watching", symbols: ["AAPL", "700.HK"], pinnedSymbols: [] }])
  assert.equal(config.barDisplay, "carousel")
  assert.equal(config.pollIntervalSeconds, 30)
  // And it writes back as v2.
  assert.equal(JSON.parse(Config.serialize(config)).version, 2)
})

test("the config round trips", () => {
  let config = Config.parse("")
  config = Config.addSymbol(config, "NVDA")
  config = Config.addList(config, "HK")
  config = Config.addSymbol(config, "700.HK")
  config = Config.setValue(config, "barDisplay", "pinned")
  config = Config.setValue(config, "pinnedSymbol", "NVDA")
  const back = roundTrip(config)
  assert.deepEqual(back.lists, config.lists)
  assert.equal(back.activeList, "HK")
  assert.equal(back.pinnedSymbol, "NVDA")
})

test("unknown keys survive a round trip untouched", () => {
  const raw = JSON.stringify({ version: 2, lists: [], someFutureOption: { nested: true } })
  const written = JSON.parse(Config.serialize(Config.parse(raw)))
  assert.deepEqual(written.someFutureOption, { nested: true })
})

test("adds land on the active list and nowhere else", () => {
  let config = Config.addList(Config.parse(""), "HK")
  config = Config.addSymbol(config, "700.HK")
  assert.deepEqual(config.lists[0].symbols, [])
  assert.deepEqual(config.lists[1].symbols, ["700.HK"])
})

test("the newest addition leads the list", () => {
  let config = Config.parse("")
  config = Config.addSymbol(config, "AAPL")
  config = Config.addSymbol(config, "NVDA")
  config = Config.addSymbol(config, "TSM")
  assert.deepEqual(Config.activeSymbols(config), ["TSM", "NVDA", "AAPL"])
})

test("the same symbol may sit on two lists; the feed sees it once", () => {
  let config = Config.addSymbol(Config.parse(""), "AAPL")
  config = Config.addList(config, "Tech")
  config = Config.addSymbol(config, "AAPL")
  assert.deepEqual(config.lists.map(l => l.symbols), [["AAPL"], ["AAPL"]])
  assert.deepEqual(Config.allSymbols(config), ["AAPL"])
})

test("a duplicate add on the same list is a no-op returning the same object", () => {
  const config = Config.addSymbol(Config.parse(""), "AAPL")
  assert.equal(Config.addSymbol(config, "00AAPL" === "x" ? "" : "AAPL"), config)
  assert.equal(Config.addSymbol(config, "garbage!!"), config)
})

test("moves stay inside the list's bounds", () => {
  let config = Config.parse("")
  // Adds prepend, so the saved order is C, B, A.
  for (const s of ["A", "B", "C"]) config = Config.addSymbol(config, s)
  assert.equal(Config.moveSymbol(config, "C", -1), config)
  assert.equal(Config.moveSymbol(config, "A", 1), config)
  const moved = Config.moveSymbol(config, "A", -1)
  assert.deepEqual(Config.activeSymbols(moved), ["C", "A", "B"])
})

test("removing a symbol repoints the pin when it named that symbol", () => {
  let config = Config.parse("")
  config = Config.addSymbol(config, "AAPL")
  config = Config.addSymbol(config, "NVDA")
  config = Config.setValue(config, "pinnedSymbol", "AAPL")
  const next = Config.removeSymbol(config, "AAPL")
  assert.equal(next.pinnedSymbol, "NVDA")
})

test("a pin on a symbol another list still holds survives the remove", () => {
  let config = Config.addSymbol(Config.parse(""), "AAPL")
  config = Config.addList(config, "Tech")
  config = Config.addSymbol(config, "AAPL")
  config = Config.setValue(config, "pinnedSymbol", "AAPL")
  // Remove from the active (second) list; the first list still has it.
  const next = Config.removeSymbol(config, "AAPL")
  assert.equal(next.pinnedSymbol, "AAPL")
})

test("list names stay unique and non-empty however they arrive", () => {
  const raw = JSON.stringify({
    version: 2,
    lists: [
      { name: "Tech", symbols: [] },
      { name: "Tech", symbols: [] },
      { name: "  ", symbols: [] }
    ]
  })
  assert.deepEqual(Config.listNames(Config.parse(raw)), ["Tech", "Tech 2", "List 3"])
  let config = Config.addList(Config.parse(""), "Watching")
  assert.deepEqual(Config.listNames(config), ["Watching", "Watching 2"])
})

test("renaming follows the active pointer and refuses collisions by suffixing", () => {
  let config = Config.addList(Config.parse(""), "HK")
  config = Config.renameList(config, "HK", "Asia")
  assert.equal(config.activeList, "Asia")
  config = Config.renameList(config, "Asia", "Watching")
  assert.deepEqual(Config.listNames(config), ["Watching", "Watching 2"])
})

test("the last list cannot be removed", () => {
  const config = Config.parse("")
  assert.equal(Config.removeList(config, config.activeList), config)
})

test("removing the active list moves the pointer to a neighbour", () => {
  let config = Config.addList(Config.parse(""), "B")
  config = Config.addList(config, "C")
  config = Config.selectList(config, "B")
  const next = Config.removeList(config, "B")
  assert.deepEqual(Config.listNames(next), ["Watching", "C"])
  assert.equal(next.activeList, "C")
})

test("selecting a list that does not exist is a no-op", () => {
  const config = Config.parse("")
  assert.equal(Config.selectList(config, "nope"), config)
})

test("setValue clamps and validates the way parse does", () => {
  const config = Config.parse("")
  assert.equal(Config.setValue(config, "pollIntervalSeconds", 1).pollIntervalSeconds, 15)
  assert.equal(Config.setValue(config, "barDisplay", "bogus").barDisplay, "icon")
  assert.equal(Config.setValue(config, "unknownKey", 1), config)
})

test("a pin is a membership on one list, scoped like the macOS app's", () => {
  let config = Config.addSymbol(Config.parse(""), "AAPL")
  config = Config.addSymbol(config, "NVDA")
  config = Config.togglePin(config, "NVDA")
  assert.deepEqual(Config.activePinnedSymbols(config), ["NVDA"])
  assert.equal(Config.isPinned(config, "NVDA"), true)
  // The same symbol on another list is not pinned there.
  config = Config.addList(config, "Tech")
  config = Config.addSymbol(config, "NVDA")
  assert.equal(Config.isPinned(config, "NVDA"), false)
  // Toggling again unpins.
  config = Config.selectList(config, "Watching")
  config = Config.togglePin(config, "NVDA")
  assert.deepEqual(Config.activePinnedSymbols(config), [])
})

test("a pin cannot outlive its symbol's membership", () => {
  let config = Config.addSymbol(Config.parse(""), "AAPL")
  config = Config.togglePin(config, "AAPL")
  config = Config.removeSymbol(config, "AAPL")
  assert.deepEqual(Config.activePinnedSymbols(config), [])
  // Pinning something not on the list is refused outright.
  const before = Config.addSymbol(Config.parse(""), "AAPL")
  assert.equal(Config.togglePin(before, "NVDA"), before)
})

test("pins and the schedule toggle round trip", () => {
  let config = Config.addSymbol(Config.parse(""), "AAPL")
  config = Config.togglePin(config, "AAPL")
  config = Config.setValue(config, "prioritizeOpenMarkets", false)
  const back = Config.parse(Config.serialize(config))
  assert.deepEqual(Config.activePinnedSymbols(back), ["AAPL"])
  assert.equal(back.prioritizeOpenMarkets, false)
  // Absent in an old file means on — the macOS default.
  assert.equal(Config.parse('{"version":2,"lists":[]}').prioritizeOpenMarkets, true)
})

test("recent searches hold the last eight, newest first, repeats refreshed", () => {
  let config = Config.parse("")
  for (let i = 1; i <= 9; i++) config = Config.recordRecentSearch(config, "q" + i)
  assert.equal(config.recentSearches.length, 8)
  assert.equal(config.recentSearches[0], "q9")
  assert.equal(config.recentSearches.indexOf("q1"), -1)
  config = Config.recordRecentSearch(config, "q5")
  assert.equal(config.recentSearches[0], "q5")
  assert.equal(config.recentSearches.filter(q => q === "q5").length, 1)
  // Blank records and clearing.
  assert.equal(Config.recordRecentSearch(config, "  "), config)
  assert.deepEqual(Config.clearRecentSearches(config).recentSearches, [])
  // And they round trip.
  assert.deepEqual(Config.parse(Config.serialize(config)).recentSearches, config.recentSearches)
})
