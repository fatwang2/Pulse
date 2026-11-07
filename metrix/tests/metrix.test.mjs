// Checks for Pulse for Metrix.Bar that run without the app: the registry entry
// matches the published file, the declared hosts match the README, and the
// Worker's symbol, search and formatting rules behave. Rendering and live
// quotes need Metrix.Bar itself (POST /v0/check, or the installed dashboard).
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const dir = new URL("../", import.meta.url);
const raw = readFileSync(new URL("pulse.bar", dir));
const source = raw.toString("utf8");
const index = JSON.parse(readFileSync(new URL("index.json", dir), "utf8"));
const readme = readFileSync(new URL("README.md", dir), "utf8");

// The Worker module, with the host's globals stubbed and test hooks appended.
const script = /<script[^>]*><!\[CDATA\[([\s\S]*)\]\]><\/script>/.exec(source)[1];
const store = new Map();
globalThis.$metrix = { invalidate() {}, schedule() {}, openURL() {} };
// English names and strings, whatever this machine's locale.
Object.defineProperty(globalThis, "navigator", { value: { language: "en-US", languages: ["en-US"] }, configurable: true });
globalThis.localStorage = {
  getItem: (k) => (store.has(k) ? store.get(k) : null),
  setItem: (k, v) => store.set(k, String(v)),
};
const scratch = mkdtempSync(join(tmpdir(), "pulse-metrix-"));
const modulePath = join(scratch, "worker.mjs");
writeFileSync(
  modulePath,
  script +
    `\nexport { normalizeSymbol, parseWatchlist, marketOf, formatPrice, fold, yahooSymbol, searchCatalog };` +
    `\nexport function useCatalog(document) { catalog = buildIndex(document); }\n`,
);
const worker = await import(pathToFileURL(modulePath).href);
rmSync(scratch, { recursive: true, force: true });

test("the registry entry describes the published file", () => {
  assert.equal(index.schema_version, 1);
  assert.equal(index.dashboards.length, 1);
  const entry = index.dashboards[0];
  assert.equal(entry.file, "pulse.bar");
  assert.equal(entry.sha256, createHash("sha256").update(raw).digest("hex"), "rebuild index.json after editing pulse.bar");
  assert.equal(entry.version, /<bar [^>]*\bversion="([^"]+)"/.exec(source)[1]);
  assert.equal(entry.id, /<bar [^>]*\bid="([^"]+)"/.exec(source)[1]);
  assert.equal(entry.name, "Pulse for Metrix.Bar");
});

test("the dashboard contacts only the hosts the README names", () => {
  const origins = [...source.matchAll(/<network origin="([^"]+)"/g)].map((m) => m[1]).sort();
  assert.deepEqual(origins, [
    "https://data-api.binance.vision",
    "https://query1.finance.yahoo.com",
    "https://www.pulseticker.app",
  ]);
  for (const origin of origins) assert.ok(readme.includes(new URL(origin).host), `README names ${origin}`);
  // Links to Pulse for Mac are tagged for this edition.
  for (const m of source.matchAll(/https:\/\/www\.pulseticker\.app\/\?[^"`\s]*/g)) assert.match(m[0], /utm_source=metrixbar/);
});

test("tickers are written the way Yahoo and Binance spell them", () => {
  assert.equal(worker.normalizeSymbol(" aapl "), "AAPL");
  assert.equal(worker.normalizeSymbol("700.hk"), "0700.HK");
  assert.equal(worker.normalizeSymbol("600519.SH"), "600519.SS");
  assert.equal(worker.normalizeSymbol("btc/usdt"), "BTC/USDT");
  assert.equal(worker.normalizeSymbol("^gspc"), "^GSPC");
  assert.throws(() => worker.normalizeSymbol("Apple Inc"));
  assert.throws(() => worker.normalizeSymbol("https://example.com"));
});

test("the starting watchlist is ordered, deduplicated and capped", () => {
  const list = worker.parseWatchlist("AAPL, aapl，0700.HK; ??? BTC/USDT");
  assert.deepEqual(list.map((e) => e.symbol), ["AAPL", "0700.HK", "???", "BTC/USDT"]);
  assert.deepEqual(list.map((e) => e.invalid), [false, false, true, false]);
  const many = Array.from({ length: 40 }, (_, i) => `T${i}`).join(",");
  assert.equal(worker.parseWatchlist(many).length, 30);
});

test("markets come from the suffix, the index list or the pair", () => {
  assert.equal(worker.marketOf("0700.HK"), "hk");
  assert.equal(worker.marketOf("600519.SS"), "sh");
  assert.equal(worker.marketOf("7203.T"), "jp");
  assert.equal(worker.marketOf("^HSI"), "hk");
  assert.equal(worker.marketOf("ETH/USDT"), "crypto");
  assert.equal(worker.marketOf("GC=F"), "metal");
  assert.equal(worker.marketOf("AAPL", "America/New_York"), "us");
});

test("prices keep each market's places without grouping", () => {
  assert.equal(worker.formatPrice(342.37, "us"), "342.37");
  assert.equal(worker.formatPrice(1453, "sh"), "1453.00");
  assert.equal(worker.formatPrice(2850, "jp"), "2850");
  assert.equal(worker.formatPrice(76053.5, "crypto"), "76053.50");
  assert.equal(worker.formatPrice(0.00000441, "crypto"), "0.00000441");
});

test("search folds case, width, accents and punctuation", () => {
  assert.equal(worker.fold("ＡＡＰＬ"), "aapl");
  assert.equal(worker.fold("BRK.B"), "brkb");
  assert.equal(worker.fold("Nestlé"), "nestle");
  assert.equal(worker.fold("腾讯 控股"), "腾讯控股");
});

test("catalog listings map to the tickers quotes are fetched under", () => {
  assert.equal(worker.yahooSymbol("hk", "700"), "0700.HK");
  assert.equal(worker.yahooSymbol("sh", "600519"), "600519.SS");
  assert.equal(worker.yahooSymbol("kq", "035720"), "035720.KQ");
  assert.equal(worker.yahooSymbol("two", "6488"), "6488.TWO");
  assert.equal(worker.yahooSymbol("us", "BRK-B"), "BRK-B");
});

test("search ranks exact over prefix over substring, then popularity", () => {
  worker.useCatalog({
    schema: 1,
    generatedAt: "2026-11-07T00:00:00Z",
    markets: ["us", "hk", "sh"],
    securities: [
      { m: "us", c: "AAPL", n: { en: "Apple Inc.", "zh-Hans": "苹果公司" }, p: 0.95 },
      { m: "us", c: "AAPU", n: { en: "Direxion Daily AAPL Bull 2X Shares" }, p: 0.2 },
      { m: "hk", c: "700", n: { en: "Tencent", "zh-Hans": "腾讯控股", "zh-Hant": "騰訊控股" }, p: 0.78 },
      { m: "us", c: "TCEHY", n: { en: "Tencent Holdings Ltd." }, p: 0.3 },
      { m: "sh", c: "600519", n: { "zh-Hans": "贵州茅台", en: "Kweichow Moutai Company" }, p: 0.73 },
    ],
    crypto: [{ b: "BTC", p: 0.8 }],
  });
  const symbols = (q) => worker.searchCatalog(q).map((r) => r.symbol);
  assert.deepEqual(symbols("aapl"), ["AAPL", "AAPU"]);
  assert.deepEqual(symbols("700"), ["0700.HK"]);
  assert.deepEqual(symbols("00700"), ["0700.HK"]);
  assert.deepEqual(symbols("tencent"), ["0700.HK", "TCEHY"]);
  assert.deepEqual(symbols("腾讯"), ["0700.HK"]);
  assert.deepEqual(symbols("騰訊"), ["0700.HK"]);
  assert.deepEqual(symbols("茅台"), ["600519.SS"]);
  assert.deepEqual(symbols("btc"), ["BTC/USDT"]);
  assert.deepEqual(symbols("spx"), ["^GSPC"]);
  // Two Latin letters match codes and name starts, never the middle of a name.
  assert.ok(!symbols("ai").includes("AAPU"));
  const [apple] = worker.searchCatalog("apple");
  assert.equal(apple.name, "Apple");
  const [bitcoin] = worker.searchCatalog("bitcoin");
  assert.equal(bitcoin.name, "Bitcoin");
});
