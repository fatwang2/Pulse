// Pulse: stock and crypto quotes beside your agents. A watchlist panel with an
// add field and a line per ticker; docked as a short strip (top or bottom), it
// draws one line of quotes. A row opens the ticker's day as a dialog: the same
// mod, given the quote in its props.
import { View, div, image, PathBuilder, Background } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { closeOverlay, exec, nextCommand, openOverlay, props, setShared, settings, shared, theme } from "herdr";
import { Watchlist, INTERVAL_MS } from "./watchlist.js";
import {
  PULSE_URLS, SESSION_LABELS, chartGeometry, formatBandPrice, formatChange, formatPrice, formatStaleDate, formatTime,
  isCryptoPair, marketSession,
} from "./quotes.js";

// The watchlist lives in Herdr's shared state (persisted), so every copy sees one list.
const STORE = "pulse.watchlist.v1";
const HEADERS = { "User-Agent": "Pulse-Herdr/0.2.0", Accept: "application/json" };
// Below this height the panel draws the one-line band.
const BAND_HEIGHT = 72;
const LOGO = "mods/pulse/icon.svg";
// Pulse's blue: the bright one on dark themes, the text-safe one on light.
const brand = () => (settings().dark === false ? "#1066C6" : "#6AB0FF");

// The site, in the system's browser: the one program the mod runs, and only on a click.
function openSite(place) {
  exec("open", [PULSE_URLS[place]]).catch(() => {});
}

export default class Pulse extends View {
  init(_props, cx) {
    const given = props() ?? {};
    if (given.detail) {
      this.detail = given.detail;
      this.overlay = given.overlay;
      return;
    }
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
    this.watch?.stop();
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

  openDetail(symbol) {
    const quote = this.watch.quotes[symbol];
    if (!quote) return;
    openOverlay({
      mod: "pulse", kind: "dialog", width: 440,
      props: { detail: { ...quote, error: this.watch.errors[symbol] ?? null } },
    });
  }

  render() {
    const t = theme();
    if (this.detail) return this.detailView(t);
    // Herdr re-renders every copy when shared state changes: adopt another copy's edit now.
    this.watch.sync();
    const root = (this.size && this.size.height < BAND_HEIGHT ? h_flex() : v_flex())
      .id("pulse").size_full().bg(t.chrome).text_color(t.foreground).text_size(12.5)
      .on_size_change((size, cx) => { this.size = size; cx.notify(); });
    return this.size && this.size.height < BAND_HEIGHT ? this.band(root, t) : this.panel(root, t);
  }

  changeColor(t, change) {
    return change === null || change === undefined ? t.dim : change >= 0 ? t.ansi2 : t.ansi1;
  }

  // The day's line, scaled to its box; the previous close is a dashed rule.
  chart(quote, color, t, { width, height, fill }) {
    const box = div().relative().flex_none().h(height);
    const sized = width === "full" ? box.w_full() : box.w(width);
    const g = chartGeometry(quote.series, quote.previousClose);
    if (!g) return sized;
    const layer = (path, paint) => window.paint_path(path, paint).absolute().top(0).left(0).size_full();
    let line = PathBuilder.stroke(fill ? 2 : 1.25);
    g.points.forEach(([x, y], i) => { line = i ? line.line_to(`${x}%`, `${y}%`) : line.move_to(`${x}%`, `${y}%`); });
    return sized
      .when(g.reference !== null, (el) => el.child(layer(
        PathBuilder.stroke(1).dash_array([3, 3]).move_to("0%", `${g.reference}%`).line_to("100%", `${g.reference}%`).build(),
        t.border)))
      .when(Boolean(fill), (el) => {
        let area = PathBuilder.fill().move_to("0%", "100%");
        for (const [x, y] of g.points) area = area.line_to(`${x}%`, `${y}%`);
        return el.child(layer(area.line_to("100%", "100%").close().build(),
          Background.solid(color).opacity(0.16)));
      })
      .child(layer(line.build(), color));
  }

  // One line: Pulse, then as many quotes as fit.
  band(root, t) {
    const w = this.watch;
    const symbols = w.preferences.symbols;
    return root.px(12).gap(14).items_center().overflow_hidden()
      .child(h_flex().flex_none().gap(6).items_center()
        .child(image(LOGO).w(14).h(14).rounded(3))
        .child(div().text_color(brand()).font_semibold().child("Pulse")))
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

  // Pulse for Mac, and the site, a click away.
  promo(t, id, compact) {
    return h_flex().id(id).gap(compact ? 7 : 10).items_center().cursor_pointer().rounded(compact ? 0 : 8)
      .when(!compact, (el) => el.p(12).bg(t.raised).hover((s) => s.bg(t.hover)))
      .on_click(() => openSite(compact ? "panel" : "detail"))
      .child(image(LOGO).flex_none().w(compact ? 16 : 30).h(compact ? 16 : 30).rounded(compact ? 4 : 7))
      .child(v_flex().flex_1().min_w(0).gap(1)
        .child(div().font_semibold().text_size(compact ? 11.5 : 12.5).text_color(brand()).truncate().child("Pulse for Mac"))
        .child(div().text_size(compact ? 10.5 : 11.5).text_color(t.dim).truncate()
          .child("Menu bar quotes, charts and positions")))
      .child(div().flex_none().text_size(compact ? 10.5 : 11.5).text_color(brand()).child("pulseticker.app ↗"));
  }

  panel(root, t) {
    const w = this.watch;
    const { paused, symbols } = w.preferences;
    const now = Date.now();
    const statusColor = paused ? t.blocked : w.loading ? t.working : t.done;
    const status = paused ? "Auto-refresh paused" : w.loading ? "Refreshing quotes…" : `Auto-refresh every ${INTERVAL_MS / 1000}s`;
    const rateLimited = w.message.includes("rate limited");

    const header = v_flex().flex_none().px(12).pt(12).gap(6)
      .child(h_flex().items_center().gap(7)
        .child(image(LOGO).flex_none().w(18).h(18).rounded(5))
        .child(div().flex_none().text_size(13.5).font_semibold().text_color(brand()).child("Pulse"))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim)
          .child(`${symbols.length} ${symbols.length === 1 ? "ticker" : "tickers"}`))
        .child(this.button(t, "pulse-refresh", "Refresh", (cx) => { this.watch.refreshNow(); cx.notify(); }))
        .child(this.button(t, "pulse-pause", paused ? "Resume" : "Pause", (cx) => this.act(cx, () => this.togglePause()))))
      .child(h_flex().items_center().gap(6)
        .child(div().flex_none().w(6).h(6).rounded_full().bg(statusColor)
          .when(w.loading, (el) => el.loop("opacity", { from: 0.35, to: 1, period: 1200 })))
        .child(div().text_size(11.5).text_color(statusColor).child(status)));

    const field = v_flex().flex_none().px(12).pt(10).gap(6)
      .child(Input.new(this.input).h(30).px(8).rounded(6).border_1()
        .border_color(this.inputFocused ? brand() : t.input).bg(t.background).text_size(12).text_color(t.foreground))
      .when(Boolean(this.error), (el) => el.child(div().text_size(11.5).text_color(t.ansi1).child(this.error)))
      .when(!this.error && Boolean(this.notice), (el) => el.child(div().text_size(11.5).text_color(t.dim).child(this.notice)))
      .when(Boolean(w.message), (el) => el.child(div().text_size(11.5).text_color(rateLimited ? t.blocked : t.dim).child(w.message)));

    const rows = symbols.map((symbol) => {
      const quote = w.quotes[symbol];
      const failed = w.errors[symbol];
      const stale = quote ? formatStaleDate(quote.timestamp, now) : "";
      const meta = quote ? [quote.name, stale && `As of ${stale}`,
        quote.delaySeconds ? `Delay ${Math.ceil(quote.delaySeconds / 60)}m` : ""].filter(Boolean).join(" · ") : "";
      const color = quote ? this.changeColor(t, quote.changePercent) : t.dim;
      return h_flex().pl(12).pr(10).gap(6).items_center().hover((s) => s.bg(t.hover))
        // The row opens the ticker's day; × sits beside it, not inside it.
        .child(v_flex().id(`pulse-row-${symbol}`).flex_1().min_w(0).py(7).gap(3).when(Boolean(quote), (el) => el.cursor_pointer())
          .on_click(() => this.openDetail(symbol))
          .child(h_flex().gap(10).items_center()
            .child(v_flex().flex_1().min_w(0).gap(1)
              .child(div().font_semibold().truncate().child(symbol))
              .when(Boolean(meta), (el) => el.child(div().text_size(11).text_color(t.dim).truncate().child(meta))))
            .when(Boolean(quote), (el) => el.child(this.chart(quote, color, t, { width: 56, height: 22 })))
            .child(v_flex().flex_none().w(108).gap(1)
              .child(div().text_right().text_color(quote && !failed ? t.foreground : t.dim)
                .child(quote ? formatPrice(quote) : failed ? "Unavailable" : paused ? "Not fetched" : "Waiting…"))
              .child(div().text_right().text_size(11).text_color(color)
                .child(quote ? formatChange(quote.changePercent) : "—"))))
          .when(Boolean(failed), (el) => el.child(div().text_size(11).text_color(t.blocked)
            .child(`${quote ? "Cached quote · " : ""}${failed}`))))
        .child(div().id(`pulse-remove-${symbol}`).flex_none().w(14).text_right().text_color(t.dim).cursor_pointer()
          .hover((s) => s.text_color(t.foreground)).on_click((_e, cx) => this.act(cx, () => this.watch.remove(symbol)))
          .child("×"));
    });

    const list = v_flex().id("pulse-list").flex_1().min_h(0).pt(8).overflow_y_scrollbar()
      .when(!symbols.length, (el) => el.child(div().px(12).py(6).text_color(t.dim)
        .child("Your watchlist is empty. Add a ticker above.")))
      .children(rows);

    const crypto = symbols.some(isCryptoPair);
    const footer = v_flex().flex_none().px(12).py(10).gap(8).border_t(1).border_color(t.border)
      .child(this.promo(t, "pulse-site", true))
      .child(div().text_size(10.5).text_color(t.dim)
        .child(crypto
          ? "Yahoo Finance · Binance Spot · Stocks: regular session, exchange delays vary · Crypto: 24h change"
          : "Yahoo Finance · Regular-session quotes · Exchange delays vary"));

    return root.child(header).child(field).child(list).child(footer);
  }

  // The dialog a row opens: the day's chart, its range and the session.
  detailView(t) {
    const q = this.detail;
    const now = Date.now();
    const color = this.changeColor(t, q.changePercent);
    const session = marketSession(q, now);
    const sessionColor = session === "open" || session === "24h" ? t.ansi2 : session === "closed" ? t.dim : t.working;
    const value = (price) => (price ? formatBandPrice({ ...q, price }) : "—");
    const stale = formatStaleDate(q.timestamp, now);
    const asOf = [`As of ${stale ? `${stale} ` : ""}${formatTime(q.timestamp)}`,
      q.delaySeconds ? `Delay ${Math.ceil(q.delaySeconds / 60)}m` : "",
      isCryptoPair(q.symbol) ? "Binance Spot · 24h" : "Yahoo Finance · regular session"].filter(Boolean).join(" · ");
    const stat = (label, price) => v_flex().flex_1().gap(2)
      .child(div().text_size(10.5).text_color(t.dim).child(label))
      .child(div().font_semibold().child(value(price)));

    return v_flex().id("pulse-detail").w_full().p(18).gap(14).text_color(t.foreground).text_size(12.5)
      .child(h_flex().items_center().gap(10)
        .child(v_flex().flex_1().min_w(0).gap(2)
          .child(div().text_size(16).font_semibold().truncate().child(q.symbol))
          .child(div().text_size(11.5).text_color(t.dim).truncate().child(q.name)))
        .child(h_flex().flex_none().gap(6).items_center().px(8).h(22).rounded(11).border_1().border_color(t.border)
          .child(div().w(6).h(6).rounded_full().bg(sessionColor))
          .child(div().text_size(11).text_color(sessionColor).child(SESSION_LABELS[session])))
        .child(div().id("pulse-detail-close").flex_none().w(18).text_right().text_size(14).text_color(t.dim).cursor_pointer()
          .hover((s) => s.text_color(t.foreground)).on_click(() => closeOverlay(this.overlay)).child("×")))
      .child(h_flex().gap(10).items_end()
        .child(div().text_size(26).font_semibold().child(formatPrice(q)))
        .child(div().pb(4).text_size(13).font_semibold().text_color(color).child(formatChange(q.changePercent))))
      .child(q.series?.length > 1
        ? this.chart(q, color, t, { width: "full", height: 140, fill: true })
        : div().h(60).flex().items_center().justify_center().text_color(t.dim).child("No intraday line yet."))
      .child(isCryptoPair(q.symbol)
        ? h_flex().gap(12).child(stat("24h open", q.open)).child(stat("24h high", q.high)).child(stat("24h low", q.low))
        : h_flex().gap(12).child(stat("Open", q.open)).child(stat("High", q.high)).child(stat("Low", q.low))
          .child(stat("Prev close", q.previousClose)))
      .child(div().text_size(11).text_color(t.dim).child(asOf))
      .when(Boolean(q.error), (el) => el.child(div().text_size(11).text_color(t.blocked).child(`Cached quote · ${q.error}`)))
      .child(this.promo(t, "pulse-detail-site", false));
  }
}
