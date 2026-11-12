// node --test rex/tests/*.test.mjs  (src/ imports nothing from Rex; the Lua is checked with `rex config check`)
import test from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { PULSE_URLS } from "../src/quotes.js";
import { PLAIN, band, cells, chartRows, detailScreen, fit, pane, strip, palette, wrap } from "../src/format.js";
import { BEGIN, END, configPath, loaderBlock, stablePaths, withBlock } from "../src/install.js";
import { createStore } from "../src/store.js";
import { Watchlist } from "../src/watchlist.js";
import { keys } from "../src/tui.js";

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

test("links to Pulse for Mac are tagged as coming from Rex", () => {
  for (const url of Object.values(PULSE_URLS)) {
    const link = new URL(url);
    assert.equal(link.origin, "https://www.pulseticker.app");
    assert.equal(link.searchParams.get("utm_source"), "rex");
    assert.equal(link.searchParams.get("utm_medium"), "plugin");
  }
});

// ---------------------------------------------------------------------------

const NOW = Date.UTC(2026, 10, 12, 16, 0);
const quote = (symbol, price, previousClose, extra = {}) => ({
  symbol, name: `${symbol} Inc.`, price, previousClose, changePercent: ((price - previousClose) / previousClose) * 100,
  currency: "USD", timestamp: NOW - 60_000, fetchedAt: NOW, delaySeconds: 0,
  series: Array.from({ length: 60 }, (_, i) => previousClose + ((price - previousClose) * i) / 59),
  open: previousClose, high: price, low: previousClose, periods: { pre: null, regular: [NOW - 1, NOW + 1], post: null },
  ...extra,
});
const state = (overrides = {}) => ({
  symbols: ["AAPL", "NVDA", "BTC/USDT"],
  quotes: { AAPL: quote("AAPL", 230.1, 227.3), NVDA: quote("NVDA", 138.4, 142.4, { delaySeconds: 900 }) },
  errors: {}, paused: false, loading: false, message: "", selected: 0, adding: false, input: "", notice: "", error: "", now: NOW,
  ...overrides,
});

test("the chart is width by height, with the previous close as a rule", () => {
  const rows = chartRows([10, 11, 12, 13], 9, 10, 4);
  assert.equal(rows.length, 4);
  for (const row of rows) assert.equal(row.map((run) => run.text).join("").length, 10);
  const text = rows.map((row) => row.map((run) => run.text).join("")).join("\n");
  assert.match(text, /┄/);
  // Four points fill four columns; the rest of the day is still empty.
  assert.match(rows.at(-1).map((run) => run.text).join(""), /^\S{4}/);
  assert.deepEqual(chartRows([1], 1, 10, 4), []);
  // The day's high stays below the top row, clear of the text above the chart.
  const tall = chartRows([10, 11, 12, 13], 9, 10, 10);
  assert.equal(tall[0].map((run) => run.text).join("").trim(), "");
});

test("every line of the pane fits its width, at any size", () => {
  for (const [width, height] of [[48, 90], [48, 24], [36, 30], [80, 20], [24, 12], [120, 50]]) {
    for (const colored of [PLAIN, palette(true)]) {
      const { lines } = pane(state(), width, height, colored);
      assert.ok(lines.length <= height, `${width}x${height}: ${lines.length} lines`);
      for (const line of lines) assert.ok(cells(line) <= width, `${width}x${height}: ${cells(line)} > ${width}: ${strip(line)}`);
    }
  }
});

test("the pane shows quotes, sources, and the selected ticker's day when there's room", () => {
  const tall = pane(state(), 48, 60).lines.join("\n");
  assert.match(tall, /◆ Pulse {2}3 tickers/);
  assert.match(tall, /AAPL .* 230\.10 USD/);
  assert.match(tall, /\+1\.23%/);
  assert.match(tall, /Delay 15m/);
  assert.match(tall, /BTC\/USDT +Waiting…/);
  assert.match(tall, /Open +High +Low +Prev close/);
  assert.match(tall, /Yahoo Finance · Binance Spot/);
  assert.match(tall, /Pulse for Mac/);
  assert.doesNotMatch(tall, /[▁▂▃▄▅▆▇]{3}.*230\.10/, "rows carry no line of their own");
  const short = pane(state(), 48, 18).lines.join("\n");
  assert.doesNotMatch(short, /Prev close/);
});

test("unknown delay is never shown as real time, and cached quotes say so", () => {
  const unknown = state({ quotes: { AAPL: quote("AAPL", 230.1, 227.3, { delaySeconds: null }) }, symbols: ["AAPL"] });
  assert.match(detailScreen(unknown.quotes.AAPL, null, NOW, 60, 30).join("\n"), /Delay unknown/);
  const cached = pane(state({ errors: { AAPL: "Yahoo rate limited requests." } }), 48, 30).lines.join("\n");
  assert.match(cached, /Cached quote · Yahoo rate limited/);
  const paused = pane(state({ paused: true }), 48, 30).lines.join("\n");
  assert.match(paused, /Auto-refresh paused/);
  assert.match(paused, /Not fetched/);
});

test("a pane six rows tall or less draws the one-line band", () => {
  const { lines } = pane(state(), 60, 6);
  assert.ok(pane(state(), 60, 7).lines.length > 1);
  assert.equal(lines.length, 1);
  assert.match(lines[0], /◆ Pulse {3}AAPL 230\.10 \+1\.23% {3}NVDA 138\.40 -2\.81%/);
  assert.ok(cells(band(state(), 30)) <= 30);
});

test("text is cut by cells, counting wide characters twice", () => {
  assert.equal(cells("腾讯控股"), 8);
  assert.equal(fit("腾讯控股有限公司", 7), "腾讯控…");
  assert.equal(fit("AAPL", 10), "AAPL");
  assert.equal(cells(palette().link("https://x.test", "Pulse")), 5);
  assert.deepEqual(wrap("Enter a ticker, such as AAPL, 0700.HK or ^GSPC", 20), ["Enter a ticker, such", "as AAPL, 0700.HK or", "^GSPC"]);
});

test("keys are read from raw terminal input", () => {
  assert.deepEqual(keys("\x1b[A\x1b[Bq\r"), [{ name: "up" }, { name: "down" }, { name: "text", text: "q" }, { name: "enter" }]);
  assert.deepEqual(keys("\x1b"), [{ name: "escape" }]);
  assert.deepEqual(keys("\x1b[<0;5;7M\x1b[<0;5;7m"), [{ name: "click", x: 5, y: 7 }]);
  // A late reply to the background-color query is skipped, not typed.
  assert.deepEqual(keys("\x1b]11;rgb:0000/0000/0000\x1b\\a"), [{ name: "text", text: "a" }]);
});

// ---------------------------------------------------------------------------

test("the watchlist file is shared: one process's edit is the next one's list", () => {
  const dir = mkdtempSync(join(tmpdir(), "pulse-rex-"));
  try {
    const host = (store) => ({ load: store.load, save: store.save, fetch: async () => { throw new Error("offline"); }, now: () => NOW, sleep: async () => {}, changed() {} });
    const one = new Watchlist(host(createStore(dir)));
    assert.deepEqual(one.preferences.symbols, ["AAPL", "NVDA", "^GSPC", "BTC/USDT"]);
    assert.equal(one.add("700.hk"), "Added 0700.HK.");
    one.pause(true);
    const two = new Watchlist(host(createStore(dir)));
    assert.ok(two.preferences.symbols.includes("0700.HK"));
    assert.equal(two.preferences.paused, true);
    assert.throws(() => two.add("Apple Inc"), /Enter a ticker/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("install adds one marked block at the end of init.lua, and uninstall takes it back out", () => {
  const block = loaderBlock("/opt/pulse/lua/pulse.lua", ["/usr/bin/node", '/opt/pu"lse/bin/pulse-rex.js']);
  assert.match(block, /dofile\("\/opt\/pulse\/lua\/pulse\.lua"\)\.setup\(\{ bin = \{ "\/usr\/bin\/node", "\/opt\/pu\\"lse\/bin\/pulse-rex\.js" \} \}\)/);
  const config = 'rex.bind("cmd+b", "client.sidebar.toggle")\n';
  const added = withBlock(config, block);
  assert.ok(added.startsWith(config));
  assert.ok(added.trimEnd().endsWith(END));
  assert.equal(withBlock(added, block), added);
  const replaced = withBlock(added, loaderBlock("/new/pulse.lua", ["pulse-rex"]));
  assert.equal(replaced.split(BEGIN).length, 2);
  assert.match(replaced, /\/new\/pulse\.lua/);
  assert.equal(withBlock(replaced, null), config);
  assert.equal(withBlock("", block), block);
  assert.equal(withBlock(config, null), config);
});

test("init.lua gets node and the package through a version manager's stable link", () => {
  const dir = mkdtempSync(join(tmpdir(), "pulse-rex-node-"));
  try {
    // …/node/node-v22/{bin/node, lib/node_modules/rex-pulse-ticker}, and …/node/current -> node-v22
    const versioned = join(dir, "node", "node-v22");
    mkdirSync(join(versioned, "bin"), { recursive: true });
    mkdirSync(join(versioned, "lib", "node_modules", "rex-pulse-ticker"), { recursive: true });
    writeFileSync(join(versioned, "bin", "node"), "");
    chmodSync(join(versioned, "bin", "node"), 0o755);
    symlinkSync(versioned, join(dir, "node", "current"));
    const stable = join(dir, "node", "current");
    const paths = stablePaths({ PATH: `/nowhere:${join(stable, "bin")}` }, join(versioned, "bin", "node"),
      join(versioned, "lib", "node_modules", "rex-pulse-ticker"));
    assert.equal(paths.node, join(stable, "bin", "node"));
    assert.equal(paths.bin, join(stable, "lib", "node_modules", "rex-pulse-ticker", "bin", "pulse-rex.js"));
    // Without such a link, the paths node reports are kept.
    const plain = stablePaths({ PATH: "/nowhere" }, join(versioned, "bin", "node"), join(versioned, "lib", "node_modules", "rex-pulse-ticker"));
    assert.equal(plain.node, join(versioned, "bin", "node"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("init.lua is found the way Rex finds it", () => {
  assert.equal(configPath({ REX_CONFIG: "/x/init.lua", HOME: "/h" }), "/x/init.lua");
  assert.equal(configPath({ XDG_CONFIG_HOME: "/c", HOME: "/h" }), "/c/rex/init.lua");
  assert.equal(configPath({ HOME: "/h" }), "/h/.config/rex/init.lua");
});

test("the Lua names every action pulse-rex's README lists", () => {
  const lua = readFileSync(here("../lua/pulse.lua"), "utf8");
  const readme = readFileSync(here("../README.md"), "utf8");
  for (const name of lua.matchAll(/name = "(pulse_\w+)"/g)) assert.ok(readme.includes(name[1]), `README misses ${name[1]}`);
});
