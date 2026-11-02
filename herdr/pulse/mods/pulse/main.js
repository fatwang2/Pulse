// Pulse: stock and crypto quotes beside your agents. A watchlist panel with an
// add field; docked as a short strip (top or bottom), it draws one line of quotes.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { nextCommand, setShared, shared, theme } from "herdr";
import { Watchlist, INTERVAL_MS } from "./watchlist.js";
import { formatBandPrice, formatChange, formatPrice, formatStaleDate, isCryptoPair } from "./quotes.js";

// The watchlist lives in Herdr's shared state (persisted), so every copy sees one list.
const STORE = "pulse.watchlist.v1";
const HEADERS = { "User-Agent": "Pulse-Herdr/0.1.0", Accept: "application/json" };
// Below this height the panel draws the one-line band.
const BAND_HEIGHT = 72;

export default class Pulse extends View {
  init(_props, cx) {
    this.size = null;
    this.typed = "";
    this.notice = "";
    this.error = "";
    this.inputFocused = false;
    this.input = InputState.new({ placeholder: "Add a ticker: AAPL, 0700.HK, BTC/USDT" });
    this.input.on("change", () => { this.typed = this.input.value(); });
    this.input.on("submit", (_e, cx) => this.add(cx));
    this.input.on("focus", (_e, cx) => { this.inputFocused = true; cx.notify(); });
    this.input.on("blur", (_e, cx) => { this.inputFocused = false; cx.notify(); });

    this.watch = new Watchlist({
      load: () => shared(STORE),
      save: (preferences) => setShared(STORE, preferences),
      // Read-only GETs to Yahoo Finance and Binance; see quotes.js for the two hosts.
      fetch: (url) => fetch(url, { headers: HEADERS }),
      now: () => Date.now(),
      sleep: () => Promise.resolve(),
      changed: () => {},
    });
    // The loop owns its own cx for its whole life: sleeping and redrawing go through it.
    cx.spawn(async (cx) => {
      this.watch.host.sleep = (ms) => cx.sleep(ms);
      this.watch.host.changed = () => cx.notify();
      await this.watch.run();
    });
    // `pulse.refresh` and `pulse.pause` (bind them in keys.json if you like).
    cx.spawn(async (cx) => {
      for (;;) {
        const command = await nextCommand();
        if (command === "refresh") this.watch.refreshNow();
        else if (command === "pause") this.togglePause();
        cx.notify();
      }
    });
  }

  close() {
    this.watch.stop();
  }

  act(cx, action) {
    this.error = "";
    try { this.notice = action() ?? ""; } catch (cause) {
      this.notice = "";
      this.error = cause instanceof Error ? cause.message : "Could not save the watchlist.";
    }
    cx.notify();
  }

  add(cx) {
    this.act(cx, () => {
      const message = this.watch.add(this.typed);
      this.input.set_value("");
      this.typed = "";
      return message;
    });
  }

  togglePause() {
    return this.watch.pause(!this.watch.preferences.paused);
  }

  render() {
    // Herdr re-renders every copy when shared state changes: adopt another copy's edit now.
    this.watch.sync();
    const t = theme();
    const root = (this.size && this.size.height < BAND_HEIGHT ? h_flex() : v_flex())
      .id("pulse").size_full().bg(t.chrome).text_color(t.foreground).text_size(12.5)
      .on_size_change((size, cx) => { this.size = size; cx.notify(); });
    return this.size && this.size.height < BAND_HEIGHT ? this.band(root, t) : this.panel(root, t);
  }

  changeColor(t, change) {
    return change === null || change === undefined ? t.dim : change >= 0 ? t.ansi2 : t.ansi1;
  }

  // One line: Pulse, then as many quotes as fit.
  band(root, t) {
    const w = this.watch;
    const symbols = w.preferences.symbols;
    return root.px(12).gap(14).items_center().overflow_hidden()
      .child(div().flex_none().text_color(t.dim).font_semibold().child("Pulse"))
      .when(w.preferences.paused, (el) => el.child(div().flex_none().text_color(t.blocked).child("Paused")))
      .when(!symbols.length, (el) => el.child(div().text_color(t.dim).truncate().child("Make the panel taller to add tickers.")))
      .children(symbols.map((symbol) => {
        const quote = w.quotes[symbol];
        const failed = Boolean(w.errors[symbol]);
        return h_flex().flex_none().gap(5).whitespace_nowrap()
          .child(div().font_semibold().child(symbol))
          .child(div().text_color(quote && !failed ? t.foreground : t.dim).child(quote ? formatBandPrice(quote) : failed ? "unavailable" : "…"))
          .when(Boolean(quote), (el) => el.child(div().text_color(this.changeColor(t, quote.changePercent)).child(formatChange(quote.changePercent))))
          .when(Boolean(quote) && failed, (el) => el.child(div().text_color(t.dim).child("cached")));
      }));
  }

  button(t, id, label, onClick) {
    return h_flex().id(id).flex_none().h(22).px(8).items_center().rounded(5).border_1().border_color(t.border)
      .text_size(11).text_color(t.muted).cursor_pointer().hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => onClick(cx)).child(label);
  }

  panel(root, t) {
    const w = this.watch;
    const { paused, symbols } = w.preferences;
    const now = Date.now();
    const statusColor = paused ? t.blocked : w.loading ? t.working : t.done;
    const status = paused ? "Auto-refresh paused" : w.loading ? "Refreshing quotes…" : `Auto-refresh every ${INTERVAL_MS / 1000}s`;
    const rateLimited = w.message.includes("rate limited");

    const header = v_flex().flex_none().px(12).pt(12).gap(6)
      .child(h_flex().items_center().gap(6)
        .child(div().flex_1().min_w(0).truncate().text_size(11).font_semibold().text_color(t.muted)
          .child(`PULSE · ${symbols.length} ${symbols.length === 1 ? "TICKER" : "TICKERS"}`))
        .child(this.button(t, "pulse-refresh", "Refresh", (cx) => { this.watch.refreshNow(); cx.notify(); }))
        .child(this.button(t, "pulse-pause", paused ? "Resume" : "Pause", (cx) => this.act(cx, () => this.togglePause()))))
      .child(h_flex().items_center().gap(6)
        .child(div().flex_none().w(6).h(6).rounded_full().bg(statusColor)
          .when(w.loading, (el) => el.loop("opacity", { from: 0.35, to: 1, period: 1200 })))
        .child(div().text_size(11.5).text_color(statusColor).child(status)));

    const field = v_flex().flex_none().px(12).pt(10).gap(6)
      .child(Input.new(this.input).h(30).px(8).rounded(6).border_1()
        .border_color(this.inputFocused ? t.accent : t.input).bg(t.background).text_size(12).text_color(t.foreground))
      .when(Boolean(this.error), (el) => el.child(div().text_size(11.5).text_color(t.ansi1).child(this.error)))
      .when(!this.error && Boolean(this.notice), (el) => el.child(div().text_size(11.5).text_color(t.dim).child(this.notice)))
      .when(Boolean(w.message), (el) => el.child(div().text_size(11.5).text_color(rateLimited ? t.blocked : t.dim).child(w.message)));

    const rows = symbols.map((symbol) => {
      const quote = w.quotes[symbol];
      const failed = w.errors[symbol];
      const stale = quote ? formatStaleDate(quote.timestamp, now) : "";
      const meta = quote ? [quote.name, stale && `As of ${stale}`,
        quote.delaySeconds ? `Delay ${Math.ceil(quote.delaySeconds / 60)}m` : ""].filter(Boolean).join(" · ") : "";
      return v_flex().id(`pulse-row-${symbol}`).px(12).py(7).gap(3).hover((s) => s.bg(t.hover))
        .child(h_flex().gap(10).items_center()
          .child(v_flex().flex_1().min_w(0).gap(1)
            .child(div().font_semibold().truncate().child(symbol))
            .when(Boolean(meta), (el) => el.child(div().text_size(11).text_color(t.dim).truncate().child(meta))))
          .child(v_flex().flex_none().gap(1)
            .child(div().text_right().text_color(quote && !failed ? t.foreground : t.dim)
              .child(quote ? formatPrice(quote) : failed ? "Unavailable" : paused ? "Not fetched" : "Waiting…"))
            .child(div().text_right().text_size(11).text_color(quote ? this.changeColor(t, quote.changePercent) : t.dim)
              .child(quote ? formatChange(quote.changePercent) : "—")))
          .child(div().id(`pulse-remove-${symbol}`).flex_none().w(14).text_right().text_color(t.dim).cursor_pointer()
            .hover((s) => s.text_color(t.foreground)).on_click((_e, cx) => this.act(cx, () => this.watch.remove(symbol)))
            .child("×")))
        .when(Boolean(failed), (el) => el.child(div().text_size(11).text_color(t.blocked)
          .child(`${quote ? "Cached quote · " : ""}${failed}`)));
    });

    const list = v_flex().id("pulse-list").flex_1().min_h(0).pt(8).overflow_y_scrollbar()
      .when(!symbols.length, (el) => el.child(div().px(12).py(6).text_color(t.dim)
        .child("Your watchlist is empty. Add a ticker above.")))
      .children(rows);

    const crypto = symbols.some(isCryptoPair);
    const footer = div().flex_none().px(12).py(10).border_t(1).border_color(t.border).text_size(10.5).text_color(t.dim)
      .child(crypto
        ? "Yahoo Finance · Binance Spot · Stocks: regular session, exchange delays vary · Crypto: 24h change · pulseticker.app"
        : "Yahoo Finance · Regular-session quotes · Exchange delays vary · pulseticker.app");

    return root.child(header).child(field).child(list).child(footer);
  }
}
