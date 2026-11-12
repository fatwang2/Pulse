// What the Pulse pane and the detail layer print: plain functions from the
// watchlist's state to lines of terminal text. No Rex imports and no I/O, so
// tests run it under Node. Colors come in as a palette, so tests can pass one
// without escape codes.
import {
  PULSE_URLS, SESSION_LABELS, formatBandPrice, formatChange, formatPrice, formatStaleDate, formatTime,
  isCryptoPair, marketSession,
} from "./quotes.js";

const BARS = "▁▂▃▄▅▆▇█";
const ESC = "\x1b[";

// ---------------------------------------------------------------------------
// Colors

const rgb = (hex) => `38;2;${parseInt(hex.slice(1, 3), 16)};${parseInt(hex.slice(3, 5), 16)};${parseInt(hex.slice(5, 7), 16)}`;
const sgr = (code) => (text) => (text ? `${ESC}${code}m${text}${ESC}0m` : "");

/** Terminal colors, so the pane follows the Rex theme; Pulse's blue is the one fixed color. */
export function palette(dark = true) {
  return {
    bold: sgr("1"),
    dim: sgr("2"),
    brand: sgr(rgb(dark ? "#6AB0FF" : "#1066C6")),
    brandBold: sgr(`1;${rgb(dark ? "#6AB0FF" : "#1066C6")}`),
    up: sgr("32"),
    down: sgr("31"),
    warn: sgr("33"),
    // A faint wash of Pulse's blue behind the row, kept through the row's own colors.
    selected: (text) => {
      const wash = `48;2;${dark ? "27;42;61" : "227;238;251"}`;
      return `${ESC}${wash}m${text.replaceAll(`${ESC}0m`, `${ESC}0;${wash}m`)}${ESC}0m`;
    },
    link: (url, text) => `\x1b]8;;${url}\x1b\\${text}\x1b]8;;\x1b\\`,
  };
}

/** The same palette with every color left out. */
export const PLAIN = {
  bold: (t) => t, dim: (t) => t, brand: (t) => t, brandBold: (t) => t, up: (t) => t, down: (t) => t,
  warn: (t) => t, selected: (t) => t, link: (_url, t) => t,
};

const tone = (colors, value) => (value === null || value === undefined ? colors.dim : value >= 0 ? colors.up : colors.down);

// ---------------------------------------------------------------------------
// Measuring

const ANSI = /\x1b\[[0-9;?]*[A-Za-z]|\x1b\]8;;[^\x1b]*\x1b\\/g;

export const strip = (text) => text.replace(ANSI, "");

/** East Asian wide and fullwidth characters take two cells. */
function wide(code) {
  return (code >= 0x1100 && code <= 0x115f) || (code >= 0x2e80 && code <= 0xa4cf && code !== 0x303f)
    || (code >= 0xac00 && code <= 0xd7a3) || (code >= 0xf900 && code <= 0xfaff) || (code >= 0xfe30 && code <= 0xfe4f)
    || (code >= 0xff00 && code <= 0xff60) || (code >= 0xffe0 && code <= 0xffe6) || (code >= 0x1f300 && code <= 0x1faff)
    || (code >= 0x20000 && code <= 0x3fffd);
}

/** The cells `text` fills once printed, escape codes left out. */
export function cells(text) {
  let width = 0;
  for (const char of strip(text)) width += wide(char.codePointAt(0)) ? 2 : 1;
  return width;
}

/** Plain text cut to `width` cells, ending in "…" when cut. */
export function fit(text, width) {
  if (width <= 0) return "";
  if (cells(text) <= width) return text;
  let out = "";
  let used = 0;
  for (const char of text) {
    const size = wide(char.codePointAt(0)) ? 2 : 1;
    if (used + size > width - 1) break;
    out += char;
    used += size;
  }
  return out + "…";
}

/** A line with escape codes cut to `width` cells, keeping its codes and closing any color it cut through. */
export function clip(line, width) {
  if (cells(line) <= width) return line;
  let out = "";
  let used = 0;
  const token = /\x1b\[[0-9;?]*[A-Za-z]|\x1b\]8;;[^\x1b]*\x1b\\|[\s\S]/gu;
  for (const [part] of line.matchAll(token)) {
    if (part.startsWith("\x1b")) { out += part; continue; }
    const size = wide(part.codePointAt(0)) ? 2 : 1;
    if (used + size > width) break;
    out += part;
    used += size;
  }
  return `${out}${ESC}0m\x1b]8;;\x1b\\`;
}

/** Plain text broken into lines of at most `width` cells, at spaces where it can be. */
export function wrap(text, width) {
  const lines = [];
  let line = "";
  for (const word of text.split(/\s+/).filter(Boolean)) {
    const next = line ? `${line} ${word}` : word;
    if (cells(next) <= width) { line = next; continue; }
    if (line) lines.push(line);
    line = cells(word) <= width ? word : fit(word, width);
  }
  if (line) lines.push(line);
  return lines;
}

const padEnd = (text, width) => text + " ".repeat(Math.max(0, width - cells(text)));
const padStart = (text, width) => " ".repeat(Math.max(0, width - cells(text))) + text;
/** `left` and `right` on one line of `width` cells, the right one flush with the edge. */
const spread = (left, right, width) => padEnd(left, width - cells(right)) + right;

// ---------------------------------------------------------------------------
// Lines and charts

/** `width` averages of `series`, one per column; a short series is stretched. */
function columns(series, width) {
  const out = [];
  for (let i = 0; i < width; i++) {
    const from = Math.floor((i * series.length) / width);
    const to = Math.max(from + 1, Math.floor(((i + 1) * series.length) / width));
    const slice = series.slice(from, Math.min(to, series.length));
    out.push(slice.reduce((sum, value) => sum + value, 0) / slice.length);
  }
  return out;
}

/**
 * The day as `height` rows of `width` cells, top row first: filled columns up to
 * each price, and the previous close as a dotted rule where no column covers it.
 * Each row is a list of runs, `{ text, kind }` with kind "bar", "rule" or "space".
 */
export function chartRows(series, reference, width, height) {
  if (!Array.isArray(series) || series.length < 2 || width < 2 || height < 1) return [];
  const values = columns(series, Math.min(width, series.length));
  const scale = typeof reference === "number" && reference > 0 ? [...values, reference] : values;
  let min = Math.min(...scale);
  let max = Math.max(...scale);
  if (max - min < max * 1e-9) { min -= 1; max += 1; }
  // Headroom: below, so the lowest price still shows a sliver of bar; above, so
  // the day's high stays clear of the price line over the chart.
  const span = max - min;
  min -= span * 0.06;
  max += span * 0.15;
  const level = (value) => ((value - min) / (max - min)) * height;
  const ruleRow = scale.length > values.length ? Math.min(height - 1, Math.floor(level(reference))) : -1;
  const rows = [];
  for (let row = height - 1; row >= 0; row--) {
    const runs = [];
    const push = (text, kind) => {
      const last = runs.at(-1);
      if (last?.kind === kind) last.text += text; else runs.push({ text, kind });
    };
    for (let column = 0; column < width; column++) {
      const fill = column < values.length ? level(values[column]) - row : 0;
      if (fill >= 1) push("█", "bar");
      else if (fill > 0) push(BARS[Math.max(0, Math.ceil(fill * BARS.length) - 1)], "bar");
      else if (row === ruleRow) push("┄", "rule");
      else push(" ", "space");
    }
    rows.push(runs);
  }
  return rows;
}

function paintChart(rows, colors, change) {
  const bar = tone(colors, change);
  return rows.map((runs) => runs.map((run) => (run.kind === "bar" ? bar(run.text) : run.kind === "rule" ? colors.dim(run.text) : run.text)).join(""));
}

// ---------------------------------------------------------------------------
// Words

/** "Delay 15m", "" for real time, and never real time when the source didn't say. */
function delayText(quote) {
  if (isCryptoPair(quote.symbol)) return "";
  if (quote.delaySeconds === null || quote.delaySeconds === undefined) return "Delay unknown";
  return quote.delaySeconds > 0 ? `Delay ${Math.round(quote.delaySeconds / 60)}m` : "";
}

function subtitle(symbol, quote, error, now) {
  if (!quote) return { text: error ?? "", warn: Boolean(error) };
  if (error) return { text: `Cached quote · ${error}`, warn: true };
  const stale = formatStaleDate(quote.timestamp, now);
  const delay = delayText(quote);
  return {
    text: [quote.name !== symbol ? quote.name : "", stale ? `As of ${stale}` : "", delay === "Delay unknown" ? "" : delay]
      .filter(Boolean).join(" · "),
    warn: false,
  };
}

const sources = (symbols) => (symbols.some(isCryptoPair)
  ? "Yahoo Finance · Binance Spot (24h change)"
  : "Yahoo Finance · Regular-session quotes · Exchange delays vary");

export const KEYS = "↑↓ select · ⏎ open · a add · x remove · r refresh · p pause · q quit";
const SHORT_KEYS = "↑↓ ⏎ open · a add · x remove · r · p · q";
const keysLine = (width) => (cells(KEYS) <= width ? KEYS : fit(SHORT_KEYS, width));

// ---------------------------------------------------------------------------
// The pane

/** A pane this many rows tall or less draws the one-line band. Rex's shortest pane is five rows. */
export const BAND_ROWS = 6;

/**
 * The Pulse pane as lines of at most `width` cells and at most `height` lines.
 * `state` is `{ symbols, quotes, errors, paused, loading, message, selected,
 * adding, input, notice, error, now }`. Returns `{ lines, rows }`, where `rows`
 * maps a line number to the index of the ticker printed there, for clicks.
 */
export function pane(state, width, height, colors = PLAIN) {
  if (height <= BAND_ROWS) return { lines: [band(state, width, colors)], rows: {} };
  const W = Math.max(1, width - 2);
  const indent = (line) => clip(` ${line}`, width);
  const rule = colors.dim("─".repeat(W));
  const { symbols } = state;

  const top = [];
  const keysHint = colors.dim("r Refresh  p " + (state.paused ? "Resume" : "Pause"));
  const title = `${colors.brandBold("◆ Pulse")}  ${colors.dim(`${symbols.length} ticker${symbols.length === 1 ? "" : "s"}`)}`;
  top.push(cells(title) + cells(keysHint) + 2 <= W ? spread(title, keysHint, W) : title);
  top.push(state.loading ? colors.brand(fit("● Refreshing quotes…", W))
    : state.paused ? colors.warn(fit("● Auto-refresh paused", W)) : colors.up(fit("● Auto-refresh every 60s", W)));
  if (state.adding) {
    top.push(`${colors.brand("›")} ${fit(state.input, W - 4)}${colors.brand("▏")}`);
    top.push(colors.dim(fit("Enter adds · Esc cancels · AAPL, 0700.HK, ^GSPC, BTC/USDT", W)));
  } else {
    top.push(colors.dim(fit("+ Add a ticker (a): AAPL, 0700.HK, BTC/USDT", W)));
  }
  const note = state.error ? colors.down(fit(state.error, W))
    : state.message ? colors.warn(fit(state.message, W))
      : state.notice ? colors.dim(fit(state.notice, W)) : "";
  if (note) top.push(note);
  top.push(rule);

  const footer = [
    rule,
    colors.dim(fit(sources(symbols), W)),
    `${colors.link(PULSE_URLS.panel, `${colors.brandBold("Pulse for Mac")} ${colors.brand("pulseticker.app ↗")}`)}${cells("Pulse for Mac pulseticker.app ↗") + 3 <= W - 20 ? colors.dim(fit("  Menu bar charts and positions", W - 31)) : ""}`,
    colors.dim(keysLine(W)),
  ];

  // The list, scrolled to keep the selection in view when it doesn't fit.
  const list = [];
  const listRows = {};
  const room = Math.max(2, height - top.length - footer.length);
  const fitsAll = symbols.length * 2 <= room;
  const visible = Math.max(1, Math.floor(room / 2));
  const first = fitsAll ? 0 : Math.min(Math.max(0, state.selected - Math.floor(visible / 2)), Math.max(0, symbols.length - visible));
  if (!symbols.length) list.push(colors.dim(fit("Your watchlist is empty. Press a to add a ticker.", W)));
  for (let i = first; i < symbols.length && list.length + 2 <= room; i++) {
    const [one, two] = tickerLines(symbols[i], state, W, colors);
    listRows[top.length + list.length] = i;
    listRows[top.length + list.length + 1] = i;
    const mark = (line) => (i === state.selected ? colors.selected(padEnd(line, W)) : line);
    list.push(mark(one), mark(two));
  }

  // The selected ticker's day fills what's left, when there is enough of it.
  const spare = height - top.length - list.length - footer.length;
  const chosen = symbols[state.selected];
  const quote = chosen ? state.quotes[chosen] : null;
  let detail = [];
  if (quote && spare >= 13) {
    // Terminal cells are about twice as tall as wide: half the width in rows draws a square chart.
    const chartHeight = Math.min(Math.round(W / 2), spare - 10);
    detail = [rule, ...detailBlock(quote, state.errors[chosen], state.now, W, chartHeight, colors)];
  }
  // The footer follows the content; what's left of a tall pane stays empty below it.
  const lines = [...top, ...list, ...detail, ...footer].slice(0, height).map(indent);
  return { lines, rows: listRows };
}

function tickerLines(symbol, state, W, colors) {
  const quote = state.quotes[symbol];
  const error = state.errors[symbol];
  const change = quote ? quote.changePercent : null;
  const paint = tone(colors, change);
  const price = quote ? formatPrice(quote) : state.paused ? "Not fetched" : "Waiting…";
  const symbolWidth = Math.max(4, W - cells(price) - 1);
  const one = spread(colors.bold(fit(symbol, symbolWidth)), quote ? price : colors.dim(price), W);
  const sub = subtitle(symbol, quote, error, state.now);
  const changeText = formatChange(change);
  const text = fit(sub.text, W - cells(changeText) - 1);
  const two = spread(sub.warn ? colors.warn(text) : colors.dim(text), paint(changeText), W);
  return [one, two];
}

/**
 * One ticker's day: name and session, price and change, the chart, the
 * open, high, low and previous close, and where the numbers come from.
 */
export function detailBlock(quote, error, now, W, chartHeight, colors = PLAIN) {
  const session = marketSession(quote, now);
  const sessionColor = session === "open" || session === "24h" ? colors.up : session === "closed" ? colors.dim : colors.warn;
  const pill = sessionColor(`● ${SESSION_LABELS[session]}`);
  const head = `${colors.bold(quote.symbol)}  ${colors.dim(fit(quote.name === quote.symbol ? "" : quote.name, Math.max(0, W - cells(quote.symbol) - cells(pill) - 4)))}`;
  const lines = [spread(head, pill, W)];
  const change = quote.changePercent;
  lines.push(`${colors.bold(formatPrice(quote))}   ${tone(colors, change)(formatChange(change))}`);
  lines.push("");
  lines.push(...paintChart(chartRows(quote.series, quote.previousClose, W, chartHeight), colors, change));
  const pair = isCryptoPair(quote.symbol);
  const labels = pair ? ["24h open", "24h high", "24h low", "24h ago"] : ["Open", "High", "Low", "Prev close"];
  const values = [quote.open, quote.high, quote.low, quote.previousClose]
    .map((value) => (typeof value === "number" ? formatPrice({ ...quote, price: value, currency: null }) : "—"));
  const column = Math.floor(W / 4);
  lines.push(labels.map((label) => padEnd(colors.dim(fit(label, column - 1)), column)).join("").trimEnd());
  lines.push(values.map((value) => padEnd(colors.bold(fit(value, column - 1)), column)).join("").trimEnd());
  const stale = formatStaleDate(quote.timestamp, now);
  const parts = [`As of ${stale ? `${stale} ` : ""}${formatTime(quote.timestamp)}`, delayText(quote), pair ? "Binance Spot · 24h" : "Yahoo Finance"]
    .filter(Boolean);
  // "regular session" only when it fits; the rest is never cut.
  const full = [...parts, ...(pair ? [] : ["regular session"])].join(" · ");
  lines.push(colors.dim(fit(cells(full) <= W ? full : parts.join(" · "), W)));
  if (error) lines.push(colors.warn(fit(`Cached quote · ${error}`, W)));
  return lines;
}

/** The detail layer: the day of one ticker, filling the layer. */
export function detailScreen(quote, error, now, width, height, colors = PLAIN) {
  const W = Math.max(30, width - 4);
  const fixed = 10 + (error ? 1 : 0);
  const chartHeight = Math.max(3, Math.min(16, height - fixed - 2));
  const block = detailBlock(quote, error, now, W, chartHeight, colors);
  const card = `${colors.link(PULSE_URLS.detail, `${colors.brandBold("Pulse for Mac")}  ${colors.dim(fit("Menu bar quotes, charts and positions", Math.max(0, W - 34)))}  ${colors.brand("pulseticker.app ↗")}`)}`;
  const lines = ["", ...block, colors.dim("─".repeat(W)), card, colors.dim("Esc closes")];
  return lines.slice(0, height).map((line) => clip(`  ${line}`, width));
}

/** The band: one line of quotes, for a pane BAND_ROWS tall or less. */
export function band(state, width, colors = PLAIN) {
  const parts = [colors.brandBold("◆ Pulse")];
  if (state.paused) parts.push(colors.warn("Paused"));
  if (!state.symbols.length) parts.push(colors.dim("Make the pane taller to add tickers."));
  for (const symbol of state.symbols) {
    const quote = state.quotes[symbol];
    if (!quote) { parts.push(`${colors.bold(symbol)} ${colors.dim("—")}`); continue; }
    const cached = state.errors[symbol] ? ` ${colors.dim("cached")}` : "";
    parts.push(`${colors.bold(symbol)} ${formatBandPrice(quote)} ${tone(colors, quote.changePercent)(formatChange(quote.changePercent))}${cached}`);
  }
  let line = " ";
  for (const part of parts) {
    const next = line === " " ? ` ${part}` : `${line}   ${part}`;
    if (cells(next) > width) break;
    line = next;
  }
  return line;
}
