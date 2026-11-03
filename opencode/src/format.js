// What the sidebar and the detail dialog print. No opencode imports, so tests
// run it under Node.
import {
  SESSION_LABELS, formatChange, formatPrice, formatStaleDate, formatTime, isCryptoPair, marketSession,
} from "./quotes.js";

const BARS = "▁▂▃▄▅▆▇█";
export const SPARK_WIDTH = 6;

/** Today's line in `width` block characters, each the mean of its slice; "" below two points. */
export function sparkline(series, width = SPARK_WIDTH) {
  if (!Array.isArray(series) || series.length < 2) return "";
  const buckets = [];
  for (let i = 0; i < width; i++) {
    const from = Math.floor((i * series.length) / width);
    const to = Math.max(from + 1, Math.floor(((i + 1) * series.length) / width));
    const slice = series.slice(from, Math.min(to, series.length));
    buckets.push(slice.length ? slice.reduce((sum, value) => sum + value, 0) / slice.length : buckets.at(-1));
  }
  const min = Math.min(...buckets);
  const max = Math.max(...buckets);
  if (max - min < max * 1e-9) return BARS[3].repeat(width);
  return buckets.map((value) => BARS[Math.round(((value - min) / (max - min)) * (BARS.length - 1))]).join("");
}

/** The day of one ticker, as the lines of the detail dialog. */
export function detailText(quote, error, now) {
  const lines = [`${formatPrice(quote)}   ${formatChange(quote.changePercent)}`, ""];
  const add = (label, value) => {
    if (value !== null && value !== undefined) lines.push(`${label.padEnd(16)}${formatPrice({ ...quote, price: value })}`);
  };
  add("Open", quote.open);
  add("High", quote.high);
  add("Low", quote.low);
  add(isCryptoPair(quote.symbol) ? "24 hours ago" : "Previous close", quote.previousClose);
  lines.push("");
  const stale = formatStaleDate(quote.timestamp, now);
  // Never present an unknown source delay as real time.
  const delay = quote.delaySeconds === null ? "delay unknown"
    : quote.delaySeconds === 0 ? "" : `delayed ${Math.round(quote.delaySeconds / 60)} min`;
  lines.push([
    SESSION_LABELS[marketSession(quote, now)],
    `${stale ? stale + " " : ""}${formatTime(quote.timestamp)}`,
    isCryptoPair(quote.symbol) ? "Binance" : "Yahoo",
    delay,
  ].filter(Boolean).join(" · "));
  if (error) lines.push("", error);
  lines.push("", "Menu bar charts: Pulse for Mac, pulseticker.app");
  return lines.join("\n");
}
