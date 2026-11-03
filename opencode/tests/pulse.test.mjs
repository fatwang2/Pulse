// node --test opencode/tests/*.test.mjs  (quotes.js, watchlist.js and format.js import nothing from opencode)
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { PULSE_URLS } from "../src/quotes.js";
import { SPARK_WIDTH, detailText, sparkline } from "../src/format.js";

const here = (path) => fileURLToPath(new URL(path, import.meta.url));
// Everything but the header comment (and, for quotes.js, PULSE_URLS) matches the Herdr mod's copy,
// whose behavior herdr/tests covers.
const body = (path) => readFileSync(here(path), "utf8")
  .replace(/^(\/\/.*\n)+/, "")
  .replace(/\/\/ The one page[\s\S]*?\n};\n/, "");

test("quotes.js and watchlist.js match the Herdr mod's", () => {
  for (const file of ["quotes.js", "watchlist.js"]) {
    assert.equal(body(`../src/${file}`), body(`../../herdr/pulse/mods/pulse/${file}`), file);
  }
});

test("links to Pulse for Mac are tagged as coming from opencode", () => {
  for (const url of Object.values(PULSE_URLS)) {
    const link = new URL(url);
    assert.equal(link.origin, "https://www.pulseticker.app");
    assert.equal(link.searchParams.get("utm_source"), "opencode");
    assert.equal(link.searchParams.get("utm_medium"), "plugin");
  }
});

test("draws today's line in block characters", () => {
  assert.equal(sparkline([]), "");
  assert.equal(sparkline([1]), "");
  assert.equal(sparkline([1, 2, 3, 4, 5, 6]), "▁▂▄▅▇█");
  assert.equal(sparkline([5, 5, 5]).length, SPARK_WIDTH);
  assert.equal(sparkline([2, 1]).length, SPARK_WIDTH);
  assert.equal(sparkline(Array.from({ length: 78 }, (_, i) => i)).length, SPARK_WIDTH);
});

test("the detail names its source and never calls an unknown delay real time", () => {
  const now = Date.UTC(2026, 10, 2, 18, 0);
  const stock = {
    symbol: "AAPL", name: "Apple Inc.", price: 230.1, changePercent: 2.2667, currency: "USD", timestamp: now,
    delaySeconds: null, series: [], open: 226, high: 231, low: 225.5, previousClose: 225, periods: null,
  };
  const text = detailText({ ...stock, periods: { pre: null, regular: [now - 1, now + 1], post: null } }, undefined, now);
  assert.match(text, /^230\.10 USD {3}\+2\.27%/);
  assert.match(text, /Previous close +225\.00 USD/);
  assert.match(text, /Market open · .* · Yahoo · delay unknown/);
  assert.match(text, /Pulse for Mac/);
  assert.doesNotMatch(text, /iPhone|iOS/);
  const pair = detailText({ ...stock, symbol: "BTC/USDT", currency: "USDT", delaySeconds: 0 }, "Binance rate limited requests.", now);
  assert.match(pair, /24 hours ago/);
  assert.match(pair, /Trades 24h · .* · Binance\n/);
  assert.match(pair, /Binance rate limited requests\./);
  assert.match(detailText({ ...stock, delaySeconds: 900 }, undefined, now), /delayed 15 min/);
});

test("the User-Agent version matches package.json, which drives the npm release", () => {
  const { version } = JSON.parse(readFileSync(here("../package.json"), "utf8"));
  assert.match(readFileSync(here("../src/tui.tsx"), "utf8"), new RegExp(`const VERSION = "${version.replace(/\./g, "\\.")}"`));
});
