// Schedule-aware watchlist ordering, ported from PulseCore's
// `WatchlistSessionOrder.swift`.
//
// The list you keep is not the list you want to read all day. At Beijing
// breakfast the US session is twelve hours stale and Hong Kong is about to
// open; after dinner the US tape is the one that is moving. So the display
// order rebuilds the rows into market blocks and leads with the session being
// traded now — while the persisted order is never touched, and stays the
// tiebreak inside every block.

.import "SymbolID.js" as SymbolID

// Presentation blocks. Shanghai and Shenzhen share one China A block so
// A-shares never interleave with other markets; both Korean boards share one
// the same way.
var BLOCKS = {
  sh: "chinaA", sz: "chinaA",
  hk: "hk",
  us: "us",
  jp: "jp",
  kr: "korea", kq: "korea",
  metal: "metal", metalCN: "metal",
  crypto: "crypto"
}

// Beijing-time schedule windows. Metals and crypto trade around the clock, so
// no window can promote them; they stay after the session-bound blocks.
// Tokyo and Seoul open at 08:00 Beijing, ahead of both Chinese markets, but
// they sit behind them here: opening first does not make them the block a
// Pulse user is watching.
var BLOCK_ORDER = {
  asiaDay: ["hk", "chinaA", "jp", "korea", "us", "metal", "crypto"],
  usEvening: ["us", "hk", "chinaA", "jp", "korea", "metal", "crypto"]
}

// 08:00..<17:00 Asia/Shanghai is the Asian trading day; everything else leads
// with the US session. Beijing has no DST, so a fixed +8 is exact.
function windowAt(nowMs) {
  var beijingHour = new Date(Number(nowMs) + 8 * 3600 * 1000).getUTCHours()
  return (beijingHour >= 8 && beijingHour < 17) ? "asiaDay" : "usEvening"
}

function blockOf(symbolKey) {
  var symbol = SymbolID.parse(symbolKey)
  return (symbol && BLOCKS[symbol.market]) || "crypto"
}

// Rebuilds `symbolKeys` into market blocks for the current window. Pins rise
// to the top of their own block — not the top of the list, because a pinned
// A-share above the US block would defeat the schedule. Relative order inside
// each pinned and unpinned slice is the caller's sequence, untouched.
function orderedSymbols(symbolKeys, pinnedKeys, nowMs) {
  var source = (symbolKeys && typeof symbolKeys.length === "number") ? symbolKeys : []
  if (source.length === 0) return []

  var pinned = {}
  var pins = (pinnedKeys && typeof pinnedKeys.length === "number") ? pinnedKeys : []
  for (var p = 0; p < pins.length; p++) pinned[pins[p]] = true

  var members = {}
  var seenBlocks = []
  for (var i = 0; i < source.length; i++) {
    var block = blockOf(source[i])
    if (!members[block]) {
      members[block] = []
      seenBlocks.push(block)
    }
    members[block].push(source[i])
  }

  var ranking = BLOCK_ORDER[windowAt(nowMs)]
  seenBlocks.sort(function (a, b) {
    var ra = ranking.indexOf(a), rb = ranking.indexOf(b)
    return (ra < 0 ? ranking.length : ra) - (rb < 0 ? ranking.length : rb)
  })

  var out = []
  for (var j = 0; j < seenBlocks.length; j++) {
    var block_ = members[seenBlocks[j]]
    for (var k = 0; k < block_.length; k++) if (pinned[block_[k]]) out.push(block_[k])
    for (var l = 0; l < block_.length; l++) if (!pinned[block_[l]]) out.push(block_[l])
  }
  return out
}

if (typeof module !== "undefined") module.exports = {
  BLOCKS: BLOCKS,
  BLOCK_ORDER: BLOCK_ORDER,
  windowAt: windowAt,
  blockOf: blockOf,
  orderedSymbols: orderedSymbols
}
