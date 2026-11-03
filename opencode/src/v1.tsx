// The opencode v1 host (opencode-ai 1.15+): slots, keymap layer, kv and dialogs from
// @opencode-ai/plugin/tui.
import type { TuiPlugin, TuiPluginApi } from "@opencode-ai/plugin/tui"
import { createSignal, Show } from "solid-js"
import { normalizeSymbol } from "./quotes.js"
import {
  Band,
  PLACEMENTS,
  Panel,
  brandColor,
  createWatch,
  detail,
  isPlacement,
  openSite,
  startingList,
  type Placement,
} from "./view.tsx"

// The watchlist, the panel's open state and the band's place, in opencode's persisted key-value store.
const STORE = "pulse.watchlist.v1"
const OPEN = "pulse.sidebar.open"
const PLACEMENT = "pulse.band.placement"

export const tui: TuiPlugin = async (api, options) => {
  const [tick, setTick] = createSignal(0)
  const watch = createWatch({
    load: () => api.kv.get(STORE, undefined) ?? startingList(options),
    save: (preferences) => api.kv.set(STORE, preferences),
    signal: api.lifecycle.signal,
    changed: () => setTick((n) => n + 1),
  })
  api.lifecycle.onDispose(() => watch.stop())

  const colors = () => {
    const theme = api.theme.current
    return {
      text: theme.text,
      muted: theme.textMuted,
      up: theme.success,
      down: theme.error,
      brand: brandColor(api.theme.mode()),
    }
  }

  const act = (action: () => string) => {
    try {
      api.ui.toast({ variant: "info", title: "Pulse", message: action() })
    } catch (error) {
      api.ui.toast({ variant: "error", title: "Pulse", message: error instanceof Error ? error.message : String(error) })
    }
    setTick((n) => n + 1)
  }

  const showDetail = (symbol: string) => {
    const shown = detail(watch, symbol)
    if (!shown) return
    api.ui.dialog.replace(() => (
      <api.ui.DialogAlert title={shown.title} message={shown.message} onConfirm={() => api.ui.dialog.clear()} />
    ))
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

  // The person's pick (kept in kv) wins over the tui.json option; "bottom" by default.
  const [placement, setPlacement] = createSignal<Placement>(
    isPlacement(api.kv.get(PLACEMENT, undefined))
      ? api.kv.get<Placement>(PLACEMENT)
      : isPlacement(options?.placement) ? (options.placement as Placement) : "bottom",
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
      {
        namespace: "palette", name: "pulse.placement", title: "Pulse: move the quote band", category: "Pulse",
        slashName: "pulse-band", run: showPlacement,
      },
    ],
  } as Parameters<TuiPluginApi["keymap"]["registerLayer"]>[0])

  const [open, setOpen] = createSignal(api.kv.get<boolean>(OPEN, true) !== false)
  const toggle = () => {
    setOpen(!open())
    api.kv.set(OPEN, open())
  }
  const band = (max?: number) => <Band colors={colors} watch={watch} tick={tick} max={max} />

  api.slots.register({
    order: 300,
    slots: {
      sidebar_content() {
        return (
          <Panel
            colors={colors}
            watch={watch}
            tick={tick}
            open={open}
            toggle={toggle}
            onDetail={showDetail}
            onLink={() => openSite("panel")}
          />
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
