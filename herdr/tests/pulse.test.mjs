// node --test herdr/tests/*.test.mjs  (quotes.js and watchlist.js import nothing from Herdr)
import test from "node:test";
import assert from "node:assert/strict";
import {
  binanceUrl, decodeBinance, decodeYahoo, formatBandPrice, formatChange, formatPrice, formatStaleDate,
  normalizeSymbol, yahooUrl, binanceKlinesUrl, decodeKlines, marketSession, chartGeometry, formatTime, STARTER_SYMBOLS, PULSE_URLS,
} from "../pulse/mods/pulse/quotes.js";
import { Watchlist, readPreferences } from "../pulse/mods/pulse/watchlist.js";

const ok = (body) => ({ status: 200, ok: true, text: JSON.stringify(body) });
const chart = (meta) => ok({ chart: { result: [{ meta }], error: null } });
const AAPL = { symbol: "AAPL", regularMarketPrice: 230.1, regularMarketTime: 1_760_000_000, previousClose: 225, currency: "USD", longName: "Apple Inc." };

test("normalizes symbols", () => {
  assert.equal(normalizeSymbol(" aapl "), "AAPL");
  assert.equal(normalizeSymbol("700.hk"), "0700.HK");
  assert.equal(normalizeSymbol("00700.HK"), "0700.HK");
  assert.equal(normalizeSymbol("600519.SH"), "600519.SS");
  assert.equal(normalizeSymbol("btc/usdt"), "BTC/USDT");
  assert.throws(() => normalizeSymbol("https://example.com"));
  assert.throws(() => normalizeSymbol("Apple Inc"));
});

test("builds the two request URLs", () => {
  assert.equal(yahooUrl("^GSPC"), "https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?interval=5m&range=1d&includePrePost=false");
  assert.equal(binanceUrl(["BTC/USDT", "ETH/USDT"]), "https://data-api.binance.vision/api/v3/ticker/24hr?symbols=" + encodeURIComponent('["BTCUSDT","ETHUSDT"]'));
});

test("decodes Yahoo quotes and refuses another ticker", () => {
  const q = decodeYahoo("AAPL", chart(AAPL), 1);
  assert.equal(q.name, "Apple Inc.");
  assert.ok(Math.abs(q.changePercent - 2.2667) < 0.001);
  assert.throws(() => decodeYahoo("MSFT", chart(AAPL), 1), /different ticker/);
  assert.throws(() => decodeYahoo("AAPL", { status: 429, ok: false, text: "" }, 1), (e) => e.retryAfterMs === 60_000);
  assert.throws(() => decodeYahoo("AAPL", { status: 200, ok: true, text: "<html>" }, 1), /unreadable/);
});

test("decodes Binance tickers", () => {
  const quotes = decodeBinance(["BTC/USDT", "ETH/USDT"], ok([
    { symbol: "BTCUSDT", lastPrice: "65000.5", prevClosePrice: "64000", closeTime: 1_760_000_000_000 },
  ]), 1);
  assert.equal(quotes["BTC/USDT"].currency, "USDT");
  assert.equal(quotes["ETH/USDT"], undefined);
  assert.throws(() => decodeBinance(["X/Y"], { status: 400, ok: false, text: "" }, 1), (e) => e.invalidSymbol);
});

test("formats without Intl", () => {
  assert.equal(formatPrice({ price: 1234567.891, currency: "USD" }), "1,234,567.89 USD");
  assert.equal(formatPrice({ price: 0.00000441, currency: null }), "0.00000441");
  assert.equal(formatPrice({ price: 0.5, currency: null }), "0.50");
  assert.equal(formatPrice({ price: 0.123456, currency: null }), "0.1235");
  assert.equal(formatBandPrice({ symbol: "AAPL", price: 230.1, currency: "USD" }), "230.10");
  assert.equal(formatBandPrice({ symbol: "BTC/USDT", price: 65000, currency: "USDT" }), "65,000.00");
  assert.equal(formatBandPrice({ symbol: "0700.HK", price: 600, currency: "HKD" }), "600.00 HKD");
  assert.equal(formatChange(1.234), "+1.23%");
  assert.equal(formatChange(-0.5), "-0.50%");
  assert.equal(formatChange(null), "—");
  const now = new Date(2026, 10, 2, 12).getTime();
  assert.equal(formatStaleDate(new Date(2026, 10, 2, 9).getTime(), now), "");
  assert.equal(formatStaleDate(new Date(2026, 9, 31, 16).getTime(), now), "Oct 31");
});

test("reads saved preferences defensively", () => {
  assert.deepEqual(readPreferences(undefined), { version: 1, symbols: STARTER_SYMBOLS, paused: false });
  assert.deepEqual(readPreferences({ version: 1, symbols: [], paused: false }), { version: 1, symbols: [], paused: false });
  assert.deepEqual(readPreferences({ version: 1, symbols: ["aapl", "AAPL", 5, "bad url"], paused: true }),
    { version: 1, symbols: ["AAPL"], paused: true });
});

// A fake host: a virtual clock, a scripted network and a shared store.
function fakeHost(respond) {
  const host = {
    store: { version: 1, symbols: [], paused: false }, clock: 0, sleeps: [], requests: [],
    load: () => host.store,
    save: (p) => { host.store = JSON.parse(JSON.stringify(p)); },
    now: () => host.clock,
    sleep: (ms) => new Promise((resolve) => host.sleeps.push({ at: host.clock + ms, resolve })),
    fetch: async (url) => { host.requests.push(url); const r = respond(url); return { ...r, text: async () => r.text }; },
    changed: () => {},
  };
  return host;
}

// Advance the clock to the next sleeper and let the loop run.
async function tick(host) {
  await new Promise((r) => setImmediate(r));
  host.sleeps.sort((a, b) => a.at - b.at);
  const next = host.sleeps.shift();
  if (!next) return false;
  host.clock = Math.max(host.clock, next.at);
  next.resolve();
  await new Promise((r) => setImmediate(r));
  return true;
}

test("refreshes stocks spaced apart and crypto in one batch", async () => {
  const host = fakeHost((url) => url.includes("binance")
    ? ok([{ symbol: "BTCUSDT", lastPrice: "65000", prevClosePrice: "64000", closeTime: 5 }])
    : chart({ ...AAPL, symbol: decodeURIComponent(url.split("/chart/")[1].split("?")[0]) }));
  const w = new Watchlist(host);
  w.add("AAPL"); w.add("MSFT"); w.add("BTC/USDT");
  const run = w.run();
  for (let i = 0; i < 6 && host.requests.length < 3; i++) await tick(host);
  assert.equal(host.requests.filter((u) => u.includes("ticker/24hr")).length, 1);
  assert.equal(host.requests.filter((u) => u.includes("yahoo")).length, 2);
  assert.ok(w.quotes.AAPL && w.quotes.MSFT && w.quotes["BTC/USDT"]);
  w.stop();
  await tick(host);
  await run;
});

test("a rate limit defers the rest of the round", async () => {
  const host = fakeHost(() => ({ status: 429, ok: false, text: "" }));
  const w = new Watchlist(host);
  w.add("AAPL"); w.add("MSFT");
  const run = w.run();
  await new Promise((r) => setImmediate(r));
  assert.match(w.errors.MSFT, /deferred/);
  assert.equal(host.requests.length, 1);
  assert.ok(w.retryAt >= 60_000);
  w.stop();
  await tick(host);
  await run;
});

test("removing a ticker drops its quote; pause stops automatic rounds", async () => {
  const host = fakeHost((url) => chart({ ...AAPL, symbol: decodeURIComponent(url.split("/chart/")[1].split("?")[0]) }));
  const w = new Watchlist(host);
  w.add("AAPL");
  const run = w.run();
  for (let i = 0; i < 3 && !w.quotes.AAPL; i++) await tick(host);
  assert.ok(w.quotes.AAPL);
  assert.equal(w.remove("AAPL"), "Removed AAPL.");
  assert.equal(w.quotes.AAPL, undefined);
  w.add("MSFT");
  w.pause(true);
  await tick(host);
  const before = host.requests.length;
  for (let i = 0; i < 3; i++) await tick(host);
  assert.equal(host.requests.length, before);
  assert.equal(host.store.paused, true);
  w.stop();
  await tick(host);
  await run;
});

test("another copy's edit is picked up at once", async () => {
  const host = fakeHost((url) => chart({ ...AAPL, symbol: decodeURIComponent(url.split("/chart/")[1].split("?")[0]) }));
  const a = new Watchlist(host);
  const b = new Watchlist(host);
  a.add("AAPL");
  assert.equal(b.sync(), true);
  assert.deepEqual(b.preferences.symbols, ["AAPL"]);
  assert.equal(b.sync(), false);
  a.pause(true);
  b.sync();
  assert.equal(b.preferences.paused, true);
  a.remove("AAPL");
  b.quotes.AAPL = {};
  b.sync();
  assert.equal(b.quotes.AAPL, undefined);
});

test("reads today's line, the day's range and the session from Yahoo", () => {
  const body = { chart: { result: [{
    meta: { ...AAPL, regularMarketDayHigh: 232, regularMarketDayLow: 224,
      currentTradingPeriod: { pre: { start: 100, end: 200 }, regular: { start: 200, end: 300 }, post: { start: 300, end: 400 } } },
    indicators: { quote: [{ open: [null, 226, 227], close: [226.5, null, 230.1], high: [227, 228, 231], low: [225, 226, 226] }] },
  }], error: null } };
  const q = decodeYahoo("AAPL", ok(body), 1);
  assert.deepEqual(q.series, [226.5, 230.1]);
  assert.equal(q.open, 226);
  assert.equal(q.high, 232);
  assert.equal(q.previousClose, 225);
  assert.equal(marketSession(q, 150_000), "pre");
  assert.equal(marketSession(q, 250_000), "open");
  assert.equal(marketSession(q, 350_000), "post");
  assert.equal(marketSession(q, 500_000), "closed");
  assert.equal(marketSession({ periods: null }, 1), "24h");
});

test("reads Binance's 24-hour line", () => {
  assert.equal(binanceKlinesUrl("BTC/USDT"), "https://data-api.binance.vision/api/v3/klines?symbol=BTCUSDT&interval=15m&limit=96");
  assert.deepEqual(decodeKlines(ok([[1, "1", "2", "0.5", "1.5"], [2, "1.5", "2", "1", "1.75"], "junk"])), [1.5, 1.75]);
  assert.throws(() => decodeKlines({ status: 400, ok: false, text: "" }));
});

test("scales a line into its box", () => {
  assert.equal(chartGeometry([1], 1), null);
  const g = chartGeometry([10, 20], 15);
  assert.deepEqual(g.points.map((p) => p[0]), [0, 100]);
  assert.ok(g.points[0][1] > g.points[1][1]);
  assert.ok(g.reference > g.points[1][1] && g.reference < g.points[0][1]);
  assert.ok(g.points.every(([, y]) => y > 0 && y < 100));
  const flat = chartGeometry([5, 5, 5], null);
  assert.equal(flat.reference, null);
  assert.equal(flat.points[0][1], 50);
  assert.match(formatTime(new Date(2026, 10, 2, 9, 5).getTime()), /^09:05$/);
});

test("the layout folder carries the same mod", async () => {
  const { readdirSync, readFileSync } = await import("node:fs");
  const mod = new URL("../pulse/mods/pulse/", import.meta.url);
  const copy = new URL("../pulse-layout/mods/pulse/", import.meta.url);
  assert.deepEqual(readdirSync(copy).sort(), readdirSync(mod).sort());
  for (const name of readdirSync(mod)) assert.ok(readFileSync(new URL(name, mod)).equals(readFileSync(new URL(name, copy))), name);
  const layout = JSON.parse(readFileSync(new URL("../pulse-layout/layouts/herdr-pulse.json", import.meta.url), "utf8"));
  assert.match(JSON.stringify(layout), /"mod":"pulse"/);
});

test("the site links say where the click came from", () => {
  for (const [place, url] of Object.entries(PULSE_URLS)) {
    const link = new URL(url);
    assert.equal(link.host, "www.pulseticker.app");
    assert.equal(link.searchParams.get("utm_source"), "herdr");
    assert.equal(link.searchParams.get("utm_medium"), "mod");
    assert.equal(link.searchParams.get("utm_content"), place);
  }
  assert.deepEqual(Object.keys(PULSE_URLS).sort(), ["detail", "panel"]);
});
