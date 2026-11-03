// The sidebar panel and the one-line quote band, shared by the opencode v1 and v2
// hosts (v1.tsx, v2.tsx). Each host passes its own theme colors and actions.
import { createMemo, For, Show } from "solid-js"
import { spawn } from "node:child_process"
import { Watchlist } from "./watchlist.js"
import { PULSE_URLS, formatBandPrice, formatChange } from "./quotes.js"
import { SPARK_WIDTH, detailText, sparkline } from "./format.js"

export const ID = "pulse-ticker"
export const VERSION = "0.2.1"
export const HEADERS = { "User-Agent": `Pulse-opencode/${VERSION}`, Accept: "application/json" }
// Pulse's blue: the bright one on dark themes, the text-safe one on light.
export const brandColor = (mode: string) => (mode === "light" ? "#1066C6" : "#6AB0FF")

// Where the one-line quote band goes; the sidebar panel is always there.
export const PLACEMENTS = {
  bottom: "Bottom line of the window",
  right: "Right of the prompt's footer (first two)",
  off: "Off (sidebar only)",
} as const
export type Placement = keyof typeof PLACEMENTS
export const isPlacement = (value: unknown): value is Placement => typeof value === "string" && value in PLACEMENTS

export type Quote = {
  symbol: string
  name: string
  price: number
  changePercent: number | null
  currency: string | null
  timestamp: number
  delaySeconds: number | null
  series: number[]
  open: number | null
  high: number | null
  low: number | null
  previousClose: number | null
  periods: unknown
}

// What the views read from watchlist.js (plain JavaScript, shared with the Herdr mod).
export type Watch = {
  preferences: { symbols: string[]; paused: boolean }
  quotes: Record<string, Quote>
  errors: Record<string, string>
  message: string
  loading: boolean
  add(input: string): string
  remove(symbol: string): string
  pause(paused: boolean): string
  refreshNow(): void
  stop(): void
  run(): Promise<void>
}

// Colors as each host's renderer takes them (RGBA in v1, strings or RGBA in v2).
export type Colors = { text: any; muted: any; up: any; down: any; brand: any }

// The site, in the system's browser: the one program the plugin runs, and only on a click.
export function openSite(place: keyof typeof PULSE_URLS) {
  const url = PULSE_URLS[place]
  const [command, args] =
    process.platform === "darwin"
      ? ["open", [url]]
      : process.platform === "win32"
        ? ["cmd", ["/c", "start", "", url]]
        : ["xdg-open", [url]]
  try {
    spawn(command, args as string[], { detached: true, stdio: "ignore" }).on("error", () => {}).unref()
  } catch {
    /* No browser to open: nothing else to do. */
  }
}

/** The watchlist, refreshing until signal aborts; load and save go to the host's own storage. */
export function createWatch(input: {
  load: () => unknown
  save: (preferences: unknown) => void
  signal: AbortSignal
  changed: () => void
}): Watch {
  const { signal } = input
  const watch: Watch = new Watchlist({
    load: input.load,
    save: input.save,
    // Read-only GETs to Yahoo Finance and Binance; see quotes.js for the two hosts.
    fetch: (url: string) => fetch(url, { headers: HEADERS, signal }),
    now: () => Date.now(),
    sleep: (ms: number) =>
      new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, ms)
        signal.addEventListener("abort", () => (clearTimeout(timer), resolve()), { once: true })
      }),
    changed: input.changed,
  })
  signal.addEventListener("abort", () => watch.stop(), { once: true })
  watch.run().catch(() => {})
  return watch
}

export function startingList(options: Record<string, unknown> | undefined) {
  const given = options?.symbols
  if (!Array.isArray(given)) return null
  return { version: 1, symbols: given.filter((item) => typeof item === "string"), paused: false }
}

/** Title and text of the detail dialog for one ticker, or null without a quote. */
export function detail(watch: Watch, symbol: string) {
  const quote = watch.quotes[symbol]
  if (!quote) return null
  return {
    title: quote.name && quote.name !== symbol ? `${symbol} · ${quote.name}` : symbol,
    message: detailText(quote, watch.errors[symbol], Date.now()),
  }
}

export function Panel(props: {
  colors: () => Colors
  watch: Watch
  tick: () => number
  open: () => boolean
  toggle: () => void
  onDetail: (symbol: string) => void
  onLink: () => void
}) {
  const c = () => props.colors()
  const rows = createMemo(() => {
    props.tick()
    return props.watch.preferences.symbols.map((symbol: string) => ({
      symbol,
      quote: props.watch.quotes[symbol],
      error: props.watch.errors[symbol],
    }))
  })
  const status = createMemo(() => {
    props.tick()
    if (props.watch.preferences.paused) return "paused"
    if (props.watch.loading && !Object.keys(props.watch.quotes).length) return "loading…"
    return ""
  })
  const message = createMemo(() => (props.tick(), props.watch.message))
  // Prices line up on the right: each one padded to the widest on the list.
  const priceWidth = createMemo(() =>
    Math.max(0, ...rows().map((row) => (row.quote ? formatBandPrice(row.quote).length : 0))),
  )
  const color = (change: number | null | undefined) =>
    change === null || change === undefined ? c().muted : change >= 0 ? c().up : c().down

  return (
    <box>
      <box flexDirection="row" gap={1} onMouseDown={props.toggle}>
        <text fg={c().text}>{props.open() ? "▼" : "▶"}</text>
        <text fg={c().text} flexGrow={1} flexShrink={1} minWidth={0} wrapMode="none" truncate>
          <b>Pulse</b>
          <Show when={status()}>
            <span style={{ fg: c().muted }}> {status()}</span>
          </Show>
        </text>
      </box>
      <Show when={props.open()}>
        <Show when={message()}>
          <text fg={c().muted}>{message()}</text>
        </Show>
        <Show when={rows().length > 0} fallback={<text fg={c().muted}>Add a ticker with /pulse-add</text>}>
          <For each={rows()}>
            {(row) => (
              <box flexDirection="row" gap={1} onMouseUp={() => props.onDetail(row.symbol)}>
                <text fg={c().text} flexGrow={1} flexShrink={1} minWidth={0} wrapMode="none" truncate>
                  {row.symbol}
                </text>
                <Show
                  when={row.quote}
                  fallback={
                    <text fg={c().muted} flexShrink={0} wrapMode="none">
                      {row.error ? "unavailable" : "—"}
                    </text>
                  }
                >
                  {(quote) => (
                    <>
                      <text fg={color(quote().changePercent)} flexShrink={0} wrapMode="none">
                        {sparkline(quote().series).padStart(SPARK_WIDTH)}
                      </text>
                      <text fg={row.error ? c().muted : c().text} flexShrink={0} wrapMode="none">
                        {formatBandPrice(quote()).padStart(priceWidth())}
                      </text>
                      <text fg={color(quote().changePercent)} flexShrink={0} wrapMode="none">
                        {formatChange(quote().changePercent).padStart(7)}
                      </text>
                    </>
                  )}
                </Show>
              </box>
            )}
          </For>
        </Show>
        <text fg={c().brand} onMouseUp={props.onLink}>
          Pulse for Mac ↗
        </text>
      </Show>
    </box>
  )
}

/** One line of quotes: symbol, price, change. Only what has a quote; cut at the edge. */
export function Band(props: { colors: () => Colors; watch: Watch; tick: () => number; max?: number }) {
  const c = () => props.colors()
  const items = createMemo(() => {
    props.tick()
    return props.watch.preferences.symbols
      .filter((symbol) => props.watch.quotes[symbol])
      .slice(0, props.max ?? Infinity)
      .map((symbol) => props.watch.quotes[symbol])
  })
  const color = (change: number | null) => (change === null ? c().muted : change >= 0 ? c().up : c().down)
  return (
    <Show when={items().length > 0}>
      <text wrapMode="none" truncate flexShrink={1} minWidth={0}>
        <For each={items()}>
          {(quote, index) => (
            <>
              <span style={{ fg: c().muted }}>{(index() ? "  " : "") + quote.symbol} </span>
              <span style={{ fg: c().text }}>{formatBandPrice(quote)} </span>
              <span style={{ fg: color(quote.changePercent) }}>{formatChange(quote.changePercent)}</span>
            </>
          )}
        </For>
      </text>
    </Show>
  )
}
