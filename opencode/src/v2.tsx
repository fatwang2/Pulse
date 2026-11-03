// The opencode v2 host (@opencode/cli 2.x): slot claims, keymap layers, storage and
// promise dialogs from @opencode/plugin/tui. Types are written out here so the
// package needs no v2 dependency.
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

// The parts of the v2 plugin context this file uses.
type Context = {
  options: Readonly<Record<string, any>>
  theme: any
  themeMode: "dark" | "light"
  storage: {
    store<Value extends object>(
      key: string,
      options: { initial: Value },
    ): readonly [Value, (mutation: (draft: Value) => void) => Promise<void>]
  }
  keymap: { layer(factory: () => { mode?: string; commands?: readonly any[] }): void }
  ui: {
    toast: { show(options: { title?: string; message: string; variant?: "info" | "success" | "warning" | "error" }): void }
    dialog: {
      alert(options: { title: string; message: string }): Promise<void>
      prompt(options: { title: string; description?: string; placeholder?: string }): Promise<string | undefined>
      select<Value>(options: {
        title: string
        options: readonly { title: string; value: Value; description?: string }[]
        current?: Value
      }): Promise<Value | undefined>
    }
    slot(claim: { append: string; render: (input: any) => any }): () => void
  }
}

export async function setup(context: Context) {
  const options = context.options
  const controller = new AbortController()
  const [tick, setTick] = createSignal(0)

  // Durable JSON in opencode's own storage. A store holds an object, so each value sits in one.
  const [saved, save] = context.storage.store<{ preferences: unknown }>("watchlist", { initial: { preferences: null } })
  const [view, saveView] = context.storage.store<{ open: boolean; placement: string | null }>("view", {
    initial: { open: true, placement: null },
  })

  // The store updates only once its file is written, so an edit is kept here until then;
  // otherwise the next read would bring back the list from before the edit.
  let unsaved: unknown = undefined
  const copy = (value: unknown) => JSON.parse(JSON.stringify(value))
  const watch = createWatch({
    load: () => copy(unsaved ?? saved.preferences ?? startingList(options)),
    save: (preferences) => {
      const value = copy(preferences)
      unsaved = value
      save((draft) => void (draft.preferences = value))
        .catch(() => {})
        .finally(() => unsaved === value && (unsaved = undefined))
    },
    signal: controller.signal,
    changed: () => setTick((n) => n + 1),
  })

  const colors = () => {
    const theme = context.theme
    return {
      text: theme.text.base,
      muted: theme.text.muted,
      up: theme.text.feedback?.success?.base ?? theme.text.base,
      down: theme.text.feedback?.error?.base ?? theme.text.base,
      brand: brandColor(context.themeMode),
    }
  }

  const toast = (message: string, variant: "info" | "error" = "info") =>
    context.ui.toast.show({ title: "Pulse", message, variant })
  const act = (action: () => string) => {
    try {
      toast(action())
    } catch (error) {
      toast(error instanceof Error ? error.message : String(error), "error")
    }
    setTick((n) => n + 1)
  }

  const showDetail = (symbol: string) => {
    const shown = detail(watch, symbol)
    if (shown) void context.ui.dialog.alert(shown)
  }
  const showAdd = async () => {
    const value = await context.ui.dialog.prompt({
      title: "Add to Pulse",
      placeholder: "AAPL, 0700.HK, ^GSPC or BTC/USDT",
    })
    if (value?.trim()) act(() => watch.add(value))
  }
  const showRemove = async () => {
    const symbols: string[] = [...watch.preferences.symbols]
    if (!symbols.length) return toast("Your watchlist is empty.")
    const symbol = await context.ui.dialog.select({
      title: "Remove from Pulse",
      options: symbols.map((value) => ({ title: value, value })),
    })
    if (symbol) act(() => watch.remove(normalizeSymbol(symbol)))
  }

  // The person's pick (kept in storage) wins over the plugin option; "bottom" by default.
  const placement = (): Placement =>
    isPlacement(view.placement) ? view.placement : isPlacement(options?.placement) ? options.placement : "bottom"
  const showPlacement = async () => {
    const value = await context.ui.dialog.select({
      title: "Pulse quote band",
      current: placement(),
      options: (Object.keys(PLACEMENTS) as Placement[]).map((value) => ({ title: PLACEMENTS[value], value })),
    })
    if (value) await saveView((draft) => void (draft.placement = value))
  }

  context.keymap.layer(() => ({
    mode: "global",
    commands: [
      { id: "pulse.add", title: "Pulse: add a ticker", group: "Pulse", palette: true, slash: { name: "pulse-add" }, run: showAdd },
      { id: "pulse.remove", title: "Pulse: remove a ticker", group: "Pulse", palette: true, slash: { name: "pulse-remove" }, run: showRemove },
      {
        id: "pulse.refresh", title: "Pulse: refresh quotes", group: "Pulse", palette: true, slash: { name: "pulse-refresh" },
        run: () => watch.refreshNow(),
      },
      {
        id: "pulse.pause", title: "Pulse: pause or resume refresh", group: "Pulse", palette: true, slash: { name: "pulse-pause" },
        run: () => act(() => watch.pause(!watch.preferences.paused)),
      },
      {
        id: "pulse.placement", title: "Pulse: move the quote band", group: "Pulse", palette: true, slash: { name: "pulse-band" },
        run: showPlacement,
      },
    ],
  }))

  const toggle = () => void saveView((draft) => void (draft.open = !draft.open))
  const band = (max?: number) => <Band colors={colors} watch={watch} tick={tick} max={max} />

  context.ui.slot({
    append: "sidebar.content",
    render: () => (
      <Panel
        colors={colors}
        watch={watch}
        tick={tick}
        open={() => view.open !== false}
        toggle={toggle}
        onDetail={showDetail}
        onLink={() => openSite("panel")}
      />
    ),
  })
  context.ui.slot({
    append: "prompt.footer",
    render: () => (
      <Show when={placement() === "right"}>
        <box flexShrink={1} minWidth={0}>{band(2)}</box>
      </Show>
    ),
  })
  context.ui.slot({
    append: "app",
    render: () => (
      <Show when={placement() === "bottom"}>
        <box flexDirection="row" flexShrink={0} paddingLeft={2} paddingRight={2}>{band()}</box>
      </Show>
    ),
  })

  return () => {
    controller.abort()
    watch.stop()
  }
}
