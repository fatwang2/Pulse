// Market identity, ported from PulseCore's `Market.swift`.
//
// Shanghai and Shenzhen stay separate because sources address them with
// different suffixes, and the two Korean boards stay separate for the same
// reason — a Korean code carries no hint of which board it belongs to. The
// display layer merges each pair back into one badge.

var MARKETS = {
  us:      { currency: "USD", timeZone: "America/New_York", utcOffsetMinutes: null, label: "US" },
  hk:      { currency: "HKD", timeZone: "Asia/Hong_Kong",   utcOffsetMinutes: 480,  label: "HK" },
  sh:      { currency: "CNY", timeZone: "Asia/Shanghai",    utcOffsetMinutes: 480,  label: "SH" },
  sz:      { currency: "CNY", timeZone: "Asia/Shanghai",    utcOffsetMinutes: 480,  label: "SZ" },
  jp:      { currency: "JPY", timeZone: "Asia/Tokyo",       utcOffsetMinutes: 540,  label: "JP" },
  kr:      { currency: "KRW", timeZone: "Asia/Seoul",       utcOffsetMinutes: 540,  label: "KR" },
  kq:      { currency: "KRW", timeZone: "Asia/Seoul",       utcOffsetMinutes: 540,  label: "KR" },
  crypto:  { currency: "USD", timeZone: "UTC",              utcOffsetMinutes: 0,    label: "CRYPTO" },
  metal:   { currency: "USD", timeZone: "America/New_York", utcOffsetMinutes: null, label: "METAL" },
  metalCN: { currency: "CNY", timeZone: "Asia/Shanghai",    utcOffsetMinutes: 480,  label: "METAL" }
}

// Both boards of a split market present as one badge, the way the macOS app
// does: which board a stock sits on is already in its symbol suffix.
var DISPLAY_LABELS = {
  us: "US", hk: "HK", sh: "CN", sz: "CN", jp: "JP", kr: "KR", kq: "KR",
  crypto: "CRYPTO", metal: "METAL", metalCN: "METAL"
}

// Rows are grouped by market and stable within a market, so a price tick never
// reorders the list. The API order inside a market is preserved.
var MARKET_ORDER = ["us", "hk", "sh", "sz", "jp", "kr", "kq", "crypto", "metal", "metalCN"]

function isKnown(market) {
  return Object.prototype.hasOwnProperty.call(MARKETS, String(market))
}

function meta(market) {
  return MARKETS[String(market)] || null
}

function currencyCode(market) {
  var m = meta(market)
  return m ? m.currency : "USD"
}

function timeZone(market) {
  var m = meta(market)
  return m ? m.timeZone : "UTC"
}

function displayLabel(market) {
  return DISPLAY_LABELS[String(market)] || String(market || "").toUpperCase()
}

function priority(market) {
  var index = MARKET_ORDER.indexOf(String(market))
  return index < 0 ? MARKET_ORDER.length : index
}

function isChinaA(market) {
  return market === "sh" || market === "sz"
}

function isKorea(market) {
  return market === "kr" || market === "kq"
}

function isMetal(market) {
  return market === "metal" || market === "metalCN"
}

// --- Sessions -------------------------------------------------------------
//
// Session windows are local exchange minutes-from-midnight. They exist to
// answer one question the refresh loop asks constantly: is it worth spending a
// request on this symbol right now. Crypto never closes, so it has no window.
//
// Tokyo's 11:30-12:30 lunch break and the Chinese 11:30-13:00 break are real
// gaps in the tape, so they are modelled as two sessions rather than one long
// one. Seoul trades straight through.

var SESSIONS = {
  us:      [[570, 960]],              // 09:30-16:00
  hk:      [[570, 720], [780, 960]],  // 09:30-12:00, 13:00-16:00
  sh:      [[570, 690], [780, 900]],  // 09:30-11:30, 13:00-15:00
  sz:      [[570, 690], [780, 900]],
  jp:      [[540, 690], [750, 930]],  // 09:00-11:30, 12:30-15:30
  kr:      [[540, 930]],              // 09:00-15:30
  kq:      [[540, 930]],
  metal:   [[0, 1440]],               // effectively round the clock
  metalCN: [[540, 900], [1260, 1440], [0, 150]]
}

// US extended sessions, in exchange-local minutes. Pre-market opens at 04:00,
// post-market runs to 20:00, and the overnight session runs 20:00 -> 04:00
// Sunday through Thursday.
var US_PRE = [240, 570]
var US_POST = [960, 1200]

function localMinutes(market, dateMs) {
  var offset = meta(market) ? meta(market).utcOffsetMinutes : 0
  // Markets with DST carry a null fixed offset and are resolved through the
  // runtime's own timezone database instead of an assumed constant.
  if (offset === null) return null
  var utc = new Date(Number(dateMs))
  return (utc.getUTCHours() * 60 + utc.getUTCMinutes() + offset + 1440) % 1440
}

function localWeekday(market, dateMs) {
  var m = meta(market)
  if (!m || m.utcOffsetMinutes === null) return null
  var shifted = new Date(Number(dateMs) + m.utcOffsetMinutes * 60000)
  return shifted.getUTCDay()
}

function withinAnySession(windows, minutes) {
  for (var i = 0; i < windows.length; i++) {
    if (minutes >= windows[i][0] && minutes < windows[i][1]) return true
  }
  return false
}

// Whether a market can be trading at `dateMs`. Weekends are excluded for
// every venue but crypto; exchange holidays are not modelled here, because a
// wrong holiday table costs a missed session and the extra polls cost little.
function isOpen(market, dateMs) {
  if (market === "crypto") return true
  var windows = SESSIONS[String(market)]
  if (!windows) return false
  var weekday = localWeekday(market, dateMs)
  var minutes = localMinutes(market, dateMs)
  if (weekday === null || minutes === null) return true // DST market: let the caller poll
  if (weekday === 0 || weekday === 6) return false
  return withinAnySession(windows, minutes)
}

if (typeof module !== "undefined") module.exports = {
  MARKETS: MARKETS,
  MARKET_ORDER: MARKET_ORDER,
  SESSIONS: SESSIONS,
  US_PRE: US_PRE,
  US_POST: US_POST,
  isKnown: isKnown,
  meta: meta,
  currencyCode: currencyCode,
  timeZone: timeZone,
  displayLabel: displayLabel,
  priority: priority,
  isChinaA: isChinaA,
  isKorea: isKorea,
  isMetal: isMetal,
  localMinutes: localMinutes,
  localWeekday: localWeekday,
  isOpen: isOpen
}
