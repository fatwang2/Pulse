// Pulse for opencode: a stock and crypto watchlist in the session sidebar.
// Each ticker shows its price, today's line and its change; click one for its
// day. Stocks and indices come from Yahoo Finance, crypto pairs (BTC/USDT)
// from Binance's public Spot data. Edit the list with /pulse-add and
// /pulse-remove; it is kept in opencode's own state (api.kv).
import type { TuiPlugin, TuiPluginApi, TuiPluginModule } from "@opencode-ai/plugin/tui"
import { createMemo, createSignal, For, Show } from "solid-js"
import { spawn } from "node:child_process"
import { Watchlist } from "./watchlist.js"
import { PULSE_URLS, formatBandPrice, formatChange, normalizeSymbol } from "./quotes.js"
import { SPARK_WIDTH, detailText, sparkline } from "./format.js"

const ID = "pulse-ticker"
const VERSION = "0.1.0"
// The watchlist and the panel's open state, in opencode's persisted key-value store.
const STORE = "pulse.watchlist.v1"
const OPEN = "pulse.sidebar.open"
const PLACEMENT = "pulse.band.placement"
// Where the one-line quote band goes; the sidebar panel is always there.
const PLACEMENTS = {
  above: "Above the prompt (on the home screen, below it)",
  right: "Right of the model name in the prompt (first two)",
  bottom: "Bottom line of the window",
  off: "Off (sidebar only)",
} as const
type Placement = keyof typeof PLACEMENTS
const isPlacement = (value: unknown): value is Placement => typeof value === "string" && value in PLACEMENTS
const HEADERS = { "User-Agent": `Pulse-opencode/${VERSION}`, Accept: "application/json" }
// Pulse's blue: the bright one on dark themes, the text-safe one on light.
const brand = (api: TuiPluginApi) => (api.theme.mode() === "light" ? "#1066C6" : "#6AB0FF")

type Quote = {
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

// What the panel reads from watchlist.js (plain JavaScript, shared with the Herdr mod).
type Watch = {
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

// The site, in the system's browser: the one program the plugin runs, and only on a click.
function openSite(place: keyof typeof PULSE_URLS) {
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

function startingList(options: Record<string, unknown> | undefined) {
  const given = options?.symbols
  if (!Array.isArray(given)) return null
  return { version: 1, symbols: given.filter((item) => typeof item === "string"), paused: false }
}

function Panel(props: { api: TuiPluginApi; watch: Watch; tick: () => number }) {
  const api = props.api
  const theme = () => api.theme.current
  const [open, setOpen] = createSignal(api.kv.get<boolean>(OPEN, true) !== false)
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
  const toggle = () => {
    const next = !open()
    setOpen(next)
    api.kv.set(OPEN, next)
  }
  const color = (change: number | null | undefined) =>
    change === null || change === undefined ? theme().textMuted : change >= 0 ? theme().success : theme().error
  const showDetail = (symbol: string) => {
    const quote = props.watch.quotes[symbol]
    if (!quote) return
    const title = quote.name && quote.name !== symbol ? `${symbol} · ${quote.name}` : symbol
    api.ui.dialog.replace(() => (
      <api.ui.DialogAlert
        title={title}
        message={detailText(quote, props.watch.errors[symbol], Date.now())}
        onConfirm={() => api.ui.dialog.clear()}
      />
    ))
  }

  return (
    <box>
      <box flexDirection="row" gap={1} onMouseDown={toggle}>
        <text fg={theme().text}>{open() ? "▼" : "▶"}</text>
        <text fg={theme().text} flexGrow={1} flexShrink={1} minWidth={0} wrapMode="none" truncate>
          <b>Pulse</b>
          <Show when={status()}>
            <span style={{ fg: theme().textMuted }}> {status()}</span>
          </Show>
        </text>
      </box>
      <Show when={open()}>
        <Show when={message()}>
          <text fg={theme().textMuted}>{message()}</text>
        </Show>
        <Show
          when={rows().length > 0}
          fallback={<text fg={theme().textMuted}>Add a ticker with /pulse-add</text>}
        >
          <For each={rows()}>
            {(row) => (
              <box flexDirection="row" gap={1} onMouseUp={() => showDetail(row.symbol)}>
                <text fg={theme().text} flexGrow={1} flexShrink={1} minWidth={0} wrapMode="none" truncate>
                  {row.symbol}
                </text>
                <Show
                  when={row.quote}
                  fallback={
                    <text fg={theme().textMuted} flexShrink={0} wrapMode="none">
                      {row.error ? "unavailable" : "—"}
                    </text>
                  }
                >
                  {(quote) => (
                    <>
                      <text fg={color(quote().changePercent)} flexShrink={0} wrapMode="none">
                        {sparkline(quote().series).padStart(SPARK_WIDTH)}
                      </text>
                      <text fg={row.error ? theme().textMuted : theme().text} flexShrink={0} wrapMode="none">
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
        <text fg={brand(api)} onMouseUp={() => openSite("panel")}>
          Pulse for Mac ↗
        </text>
      </Show>
    </box>
  )
}

/** One line of quotes: symbol, price, change. Only what has a quote; cut at the edge. */
function Band(props: { api: TuiPluginApi; watch: Watch; tick: () => number; max?: number }) {
  const theme = () => props.api.theme.current
  const items = createMemo(() => {
    props.tick()
    return props.watch.preferences.symbols
      .filter((symbol) => props.watch.quotes[symbol])
      .slice(0, props.max ?? Infinity)
      .map((symbol) => props.watch.quotes[symbol])
  })
  const color = (change: number | null) =>
    change === null ? theme().textMuted : change >= 0 ? theme().success : theme().error
  return (
    <Show when={items().length > 0}>
      <text wrapMode="none" truncate flexShrink={1} minWidth={0}>
        <For each={items()}>
          {(quote, index) => (
            <>
              <span style={{ fg: theme().textMuted }}>{(index() ? "  " : "") + quote.symbol} </span>
              <span style={{ fg: theme().text }}>{formatBandPrice(quote)} </span>
              <span style={{ fg: color(quote.changePercent) }}>{formatChange(quote.changePercent)}</span>
            </>
          )}
        </For>
      </text>
    </Show>
  )
}

const tui: TuiPlugin = async (api, options) => {
  const [tick, setTick] = createSignal(0)
  const signal = api.lifecycle.signal
  const watch: Watch = new Watchlist({
    load: () => api.kv.get(STORE, undefined) ?? startingList(options),
    save: (preferences: unknown) => api.kv.set(STORE, preferences),
    // Read-only GETs to Yahoo Finance and Binance; see quotes.js for the two hosts.
    fetch: (url: string) => fetch(url, { headers: HEADERS, signal }),
    now: () => Date.now(),
    sleep: (ms: number) =>
      new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, ms)
        signal.addEventListener("abort", () => (clearTimeout(timer), resolve()), { once: true })
      }),
    changed: () => setTick((n) => n + 1),
  })
  api.lifecycle.onDispose(() => watch.stop())
  watch.run().catch(() => {})

  const act = (action: () => string) => {
    try {
      api.ui.toast({ variant: "info", title: "Pulse", message: action() })
    } catch (error) {
      api.ui.toast({ variant: "error", title: "Pulse", message: error instanceof Error ? error.message : String(error) })
    }
    setTick((n) => n + 1)
  }

  const showAdd = () =>
    api.ui.dialog.replace(() => (
      <api.ui.DialogPrompt
        title="Add to Pulse"
        placeholder="AAPL, 0700.HK, ^GSPC or BTC/USDT"
        onConfirm={(value) => {
          api.ui.dialog.clear()
          if (value.trim()) act(() => watch.add(value))
        }}
        onCancel={() => api.ui.dialog.clear()}
      />
    ))

  const showRemove = () => {
    const symbols: string[] = watch.preferences.symbols
    if (!symbols.length) return api.ui.toast({ variant: "info", title: "Pulse", message: "Your watchlist is empty." })
    api.ui.dialog.replace(() => (
      <api.ui.DialogSelect
        title="Remove from Pulse"
        options={symbols.map((symbol) => ({ title: symbol, value: symbol }))}
        onSelect={(option) => {
          api.ui.dialog.clear()
          act(() => watch.remove(normalizeSymbol(option.value)))
        }}
      />
    ))
  }

  api.keymap.registerLayer({
    commands: [
      { namespace: "palette", name: "pulse.add", title: "Pulse: add a ticker", category: "Pulse", slashName: "pulse-add", run: showAdd },
      { namespace: "palette", name: "pulse.remove", title: "Pulse: remove a ticker", category: "Pulse", slashName: "pulse-remove", run: showRemove },
      {
        namespace: "palette", name: "pulse.refresh", title: "Pulse: refresh quotes", category: "Pulse", slashName: "pulse-refresh",
        run: () => watch.refreshNow(),
      },
      {
        namespace: "palette", name: "pulse.pause", title: "Pulse: pause or resume refresh", category: "Pulse", slashName: "pulse-pause",
        run: () => act(() => watch.pause(!watch.preferences.paused)),
      },
    ],
  } as Parameters<TuiPluginApi["keymap"]["registerLayer"]>[0])

  // The person's pick (kept in kv) wins over the tui.json option; "above" by default.
  const [placement, setPlacement] = createSignal<Placement>(
    isPlacement(api.kv.get(PLACEMENT, undefined))
      ? api.kv.get<Placement>(PLACEMENT)
      : isPlacement(options?.placement) ? (options.placement as Placement) : "above",
  )
  const showPlacement = () =>
    api.ui.dialog.replace(() => (
      <api.ui.DialogSelect
        title="Pulse quote band"
        current={placement()}
        options={(Object.keys(PLACEMENTS) as Placement[]).map((value) => ({ title: PLACEMENTS[value], value }))}
        onSelect={(option) => {
          api.ui.dialog.clear()
          setPlacement(option.value)
          api.kv.set(PLACEMENT, option.value)
        }}
      />
    ))
  const band = (max?: number) => <Band api={api} watch={watch} tick={tick} max={max} />

  api.keymap.registerLayer({
    commands: [
      {
        namespace: "palette", name: "pulse.placement", title: "Pulse: move the quote band", category: "Pulse",
        slashName: "pulse-band", run: showPlacement,
      },
    ],
  } as Parameters<TuiPluginApi["keymap"]["registerLayer"]>[0])

  api.slots.register({
    order: 300,
    slots: {
      sidebar_content() {
        return <Panel api={api} watch={watch} tick={tick} />
      },
      // opencode has no slot above the prompt: in "above", this draws the band and
      // opencode's own Prompt under it. Otherwise it draws nothing, so opencode keeps its prompt.
      session_prompt(_ctx, props) {
        // Nothing (not an empty Show) unless "above": opencode then draws its own prompt.
        if (placement() !== "above") return null
        return (
          <box>
            <box paddingLeft={2} flexDirection="row">{band()}</box>
            <api.ui.Prompt
              sessionID={props.session_id}
              visible={props.visible}
              disabled={props.disabled}
              onSubmit={props.on_submit}
              ref={props.ref}
              right={<api.ui.Slot name="session_prompt_right" session_id={props.session_id} />}
            />
          </box>
        )
      },
      home_bottom() {
        return (
          <Show when={placement() === "above"}>
            <box flexDirection="row" justifyContent="center" paddingTop={1}>{band()}</box>
          </Show>
        )
      },
      session_prompt_right() {
        return <Show when={placement() === "right"}>{band(2)}</Show>
      },
      home_prompt_right() {
        return <Show when={placement() === "right"}>{band(2)}</Show>
      },
      app_bottom() {
        return (
          <Show when={placement() === "bottom"}>
            <box flexDirection="row" paddingLeft={2} paddingRight={2}>{band()}</box>
          </Show>
        )
      },
    },
  })
}

const plugin: TuiPluginModule & { id: string } = { id: ID, tui }
export default plugin
