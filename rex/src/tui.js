// The programs Rex runs in a pane: the watchlist, the detail layer, and the
// add prompt. Everything they print comes from format.js.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { QuoteError } from "./quotes.js";
import { Watchlist } from "./watchlist.js";
import { createStore } from "./store.js";
import { detailScreen, fit, pane, palette, wrap } from "./format.js";

export const VERSION = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")).version;
const HEADERS = { "User-Agent": `Pulse-Rex/${VERSION}`, Accept: "application/json" };
// Points sent along to the detail layer; plenty for a chart a terminal wide.
const DETAIL_POINTS = 160;

// ---------------------------------------------------------------------------
// The terminal

const out = (text) => process.stdout.write(text);

function screen() {
  const { stdin, stdout } = process;
  let open = false;
  const api = {
    get width() { return stdout.columns || 48; },
    get height() { return stdout.rows || 24; },
    start(mouse) {
      open = true;
      out("\x1b[?1049h\x1b[?25l" + (mouse ? "\x1b[?1000h\x1b[?1006h" : ""));
      if (stdin.isTTY) stdin.setRawMode(true);
      stdin.resume();
    },
    draw(lines) {
      out("\x1b[H" + lines.map((line) => line + "\x1b[K").join("\r\n") + "\x1b[J");
    },
    stop() {
      if (!open) return;
      open = false;
      out("\x1b[?1000l\x1b[?1006l\x1b[?25h\x1b[?1049l");
      if (stdin.isTTY) stdin.setRawMode(false);
      stdin.pause();
    },
  };
  return api;
}

/** Asks the terminal for its background (OSC 11), to pick Pulse's blue for it. Dark when it doesn't say. */
function detectDark(timeoutMs = 150) {
  const { stdin } = process;
  if (!stdin.isTTY) return Promise.resolve(true);
  return new Promise((resolve) => {
    let reply = "";
    const done = (dark) => { clearTimeout(timer); stdin.off("data", listen); resolve(dark); };
    const listen = (data) => {
      reply += data.toString();
      const match = /\]11;rgb:([0-9a-f]+)\/([0-9a-f]+)\/([0-9a-f]+)/i.exec(reply);
      if (!match) return;
      const [r, g, b] = match.slice(1).map((hex) => parseInt(hex, 16) / (16 ** hex.length - 1));
      done(0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5);
    };
    const timer = setTimeout(() => done(true), timeoutMs);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.on("data", listen);
    out("\x1b]11;?\x1b\\");
  });
}

/** Splits raw input into keys: named ones, printable text, and clicks. */
export function keys(data) {
  const found = [];
  let rest = data;
  const named = [
    ["\x1b[A", "up"], ["\x1bOA", "up"], ["\x1b[B", "down"], ["\x1bOB", "down"],
    ["\x1b[5~", "pageup"], ["\x1b[6~", "pagedown"], ["\x1b[3~", "delete"],
    ["\r", "enter"], ["\n", "enter"], ["\x7f", "backspace"], ["\b", "backspace"], ["\x03", "interrupt"],
  ];
  while (rest.length) {
    const click = /^\x1b\[<(\d+);(\d+);(\d+)([Mm])/.exec(rest);
    if (click) {
      if (click[4] === "M" && Number(click[1]) === 0) found.push({ name: "click", x: Number(click[2]), y: Number(click[3]) });
      if (click[4] === "M" && Number(click[1]) === 64) found.push({ name: "up" });
      if (click[4] === "M" && Number(click[1]) === 65) found.push({ name: "down" });
      rest = rest.slice(click[0].length);
      continue;
    }
    const hit = named.find(([sequence]) => rest.startsWith(sequence));
    if (hit) { found.push({ name: hit[1] }); rest = rest.slice(hit[0].length); continue; }
    if (rest[0] === "\x1b") {
      // A sequence we don't use (or a reply to a query): skip it whole. A lone Esc is Escape.
      const other = /^\x1b(\[[0-9;?<>]*[ -\/]*[@-~]|\][^\x07\x1b]*(\x07|\x1b\\)|O.)/.exec(rest);
      if (other) { rest = rest.slice(other[0].length); continue; }
      found.push({ name: "escape" });
      rest = rest.slice(1);
      continue;
    }
    const char = String.fromCodePoint(rest.codePointAt(0));
    if (char >= " ") found.push({ name: "text", text: char });
    rest = rest.slice(char.length);
  }
  return found;
}

function host(store) {
  return {
    load: () => store.load(),
    save: (preferences) => store.save(preferences),
    fetch: (url) => fetch(url, { headers: HEADERS, signal: AbortSignal.timeout(15_000) }),
    now: () => Date.now(),
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    changed: () => {},
  };
}

/** Opens one ticker's day in a Rex floating layer; false when this isn't a Rex pane or it failed. */
function openLayer(quote, bin) {
  const session = process.env.REX_SESSION;
  if (!session) return false;
  const step = Math.max(1, Math.ceil(quote.series.length / DETAIL_POINTS));
  const sent = { ...quote, series: quote.series.filter((_, i) => i % step === 0 || i === quote.series.length - 1) };
  const request = {
    session_id: session,
    bounds: [0.18, 0.12, 0.64, 0.66],
    focus: true,
    layout: { block: {
      flavor: "com.superlogical.terminal.shell",
      label: `Pulse · ${quote.symbol}`,
      options: { command: [...bin, "detail", "--quote", JSON.stringify(sent)] },
    } },
  };
  const result = spawnSync("rex", ["api", "call", "-s", session, "session.new_layer", "-"], {
    input: JSON.stringify(request), encoding: "utf8", timeout: 10_000,
  });
  return result.status === 0;
}

/**
 * Moves the border between this pane and the one it was opened beside, so
 * Pulse gets the width it was opened for. The Rex app evens out a new split
 * once it shows it, so this runs after a moment, and once more in case the
 * app was slow.
 */
function fitWidth(fit) {
  const session = process.env.REX_SESSION;
  const self = process.env.REX_BLOCK;
  if (!fit || !session || !self) return;
  const resize = () => spawnSync("rex", ["api", "call", "-s", session, "session.resize_pane", "-"], {
    input: JSON.stringify({ direction: "horizontal", before_block_id: fit.beside, after_block_id: self, ratio: fit.ratio }),
    encoding: "utf8", timeout: 5_000,
  });
  setTimeout(resize, 400).unref();
  setTimeout(resize, 1500).unref();
}

// ---------------------------------------------------------------------------
// The watchlist pane

export async function runPane(bin, fit = null) {
  const store = createStore();
  const term = screen();
  const colors = palette(await detectDark());
  const watch = new Watchlist(host(store));
  const ui = { selected: 0, adding: false, input: "", notice: "", error: "", inline: null, rows: {} };
  let scheduled = false;

  const state = () => ({
    symbols: watch.preferences.symbols,
    quotes: watch.quotes,
    errors: watch.errors,
    paused: watch.preferences.paused,
    loading: watch.loading,
    message: watch.message,
    selected: ui.selected,
    adding: ui.adding,
    input: ui.input,
    notice: ui.notice,
    error: ui.error,
    now: Date.now(),
  });

  const draw = () => {
    scheduled = false;
    const count = watch.preferences.symbols.length;
    ui.selected = Math.max(0, Math.min(ui.selected, count - 1));
    if (ui.inline) {
      const quote = watch.quotes[ui.inline];
      if (!quote) ui.inline = null;
      else { term.draw(detailScreen(quote, watch.errors[ui.inline], Date.now(), term.width, term.height, colors)); return; }
    }
    const drawn = pane(state(), term.width, term.height, colors);
    ui.rows = drawn.rows;
    term.draw(drawn.lines);
  };
  const redraw = () => {
    if (scheduled) return;
    scheduled = true;
    setImmediate(draw);
  };
  watch.host.changed = redraw;

  const quit = () => {
    watch.stop();
    store.close();
    term.stop();
    process.exit(0);
  };

  const say = (run) => {
    ui.error = "";
    try { ui.notice = run(); } catch (error) {
      ui.notice = "";
      ui.error = error instanceof QuoteError ? error.message : String(error?.message ?? error);
    }
  };

  const open = () => {
    const symbol = watch.preferences.symbols[ui.selected];
    const quote = symbol && watch.quotes[symbol];
    if (!quote) { ui.notice = symbol ? `${symbol} has no quote yet.` : ""; return; }
    if (!openLayer(quote, bin)) ui.inline = symbol;
  };

  const onKey = (key) => {
    if (key.name === "interrupt") return quit();
    if (ui.inline) {
      if (["escape", "enter", "interrupt"].includes(key.name) || key.text === "q") ui.inline = null;
      return;
    }
    if (ui.adding) {
      if (key.name === "escape") { ui.adding = false; ui.input = ""; ui.error = ""; }
      else if (key.name === "enter") {
        const typed = ui.input.trim();
        if (!typed) { ui.adding = false; return; }
        say(() => watch.add(typed));
        if (!ui.error) {
          ui.adding = false;
          ui.input = "";
          ui.selected = watch.preferences.symbols.length - 1;
        }
      } else if (key.name === "backspace") ui.input = [...ui.input].slice(0, -1).join("");
      else if (key.name === "text" && ui.input.length < 40) ui.input += key.text;
      return;
    }
    const count = watch.preferences.symbols.length;
    ui.error = "";
    switch (key.name) {
      case "up": ui.selected = (ui.selected + count - 1) % Math.max(1, count); return;
      case "down": ui.selected = (ui.selected + 1) % Math.max(1, count); return;
      case "pageup": ui.selected = 0; return;
      case "pagedown": ui.selected = count - 1; return;
      case "enter": open(); return;
      case "delete": case "backspace": remove(); return;
      case "escape": ui.notice = ""; return;
      case "click": {
        const index = ui.rows[key.y - 1];
        if (index === undefined) return;
        if (index === ui.selected) open(); else ui.selected = index;
        return;
      }
      default: break;
    }
    if (key.name !== "text") return;
    switch (key.text) {
      case "q": quit(); return;
      case "k": onKey({ name: "up" }); return;
      case "j": onKey({ name: "down" }); return;
      case "a": case "+": ui.adding = true; ui.input = ""; ui.notice = ""; return;
      case "x": case "-": remove(); return;
      case "r": watch.refreshNow(); ui.notice = "Refreshing now."; return;
      case "p": say(() => watch.pause(!watch.preferences.paused)); return;
      default: break;
    }
  };
  const remove = () => {
    const symbol = watch.preferences.symbols[ui.selected];
    if (symbol) say(() => watch.remove(symbol));
  };

  term.start(true);
  fitWidth(fit);
  process.stdin.on("data", (data) => {
    for (const key of keys(data.toString())) onKey(key);
    draw();
  });
  process.stdout.on("resize", draw);
  process.on("SIGHUP", quit);
  process.on("SIGTERM", quit);
  store.watch(() => { if (watch.sync()) redraw(); }, () => watch.refreshNow());
  // Market sessions and "As of" dates move with the clock, between rounds too.
  setInterval(redraw, 30_000).unref();
  draw();
  await watch.run();
}

// ---------------------------------------------------------------------------
// The detail layer: the quote it was given, as it was. It fetches nothing.

export async function runDetail(json) {
  let quote;
  try { quote = JSON.parse(json); } catch { quote = null; }
  if (!quote?.symbol) {
    process.stderr.write("pulse-rex detail: expected --quote with a quote from the Pulse pane.\n");
    process.exit(2);
  }
  const term = screen();
  const colors = palette(await detectDark());
  const draw = () => term.draw(detailScreen(quote, null, Date.now(), term.width, term.height, colors));
  const quit = () => { term.stop(); process.exit(0); };
  term.start(false);
  process.stdin.on("data", (data) => {
    if (keys(data.toString()).some((key) => ["escape", "enter", "interrupt"].includes(key.name) || key.text === "q")) quit();
  });
  process.stdout.on("resize", draw);
  process.on("SIGHUP", quit);
  draw();
}

// ---------------------------------------------------------------------------
// The add prompt, for the palette's "Pulse: Add Ticker…"

export async function runPrompt() {
  const store = createStore();
  const watch = new Watchlist(host(store));
  const term = screen();
  const colors = palette(await detectDark());
  let input = "";
  let error = "";
  const draw = () => {
    const W = Math.max(20, term.width - 4);
    term.draw([
      "",
      `  ${colors.brandBold("◆ Pulse")}  ${colors.dim("Add a ticker")}`,
      "",
      `  ${colors.brand("›")} ${input}${colors.brand("▏")}`,
      "",
      ...(error ? wrap(error, W).map((line) => `  ${colors.down(line)}`) : [`  ${colors.dim(fit("AAPL, 0700.HK, ^GSPC, BTC/USDT", W))}`]),
      `  ${colors.dim("Enter adds · Esc cancels")}`,
    ]);
  };
  const quit = () => { term.stop(); process.exit(0); };
  term.start(false);
  process.stdin.on("data", (data) => {
    for (const key of keys(data.toString())) {
      if (key.name === "escape" || key.name === "interrupt") return quit();
      if (key.name === "enter") {
        if (!input.trim()) return quit();
        try { watch.add(input.trim()); return quit(); } catch (cause) {
          error = cause instanceof QuoteError ? cause.message : String(cause?.message ?? cause);
        }
      } else if (key.name === "backspace") input = [...input].slice(0, -1).join("");
      else if (key.name === "text" && input.length < 40) { input += key.text; error = ""; }
    }
    draw();
  });
  process.stdout.on("resize", draw);
  process.on("SIGHUP", quit);
  draw();
}
