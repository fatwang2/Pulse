// The watchlist and its refresh loop. Herdr's APIs come in through `host`,
// so tests drive it under Node with a fake clock and network.
import {
  BINANCE_BATCH, QuoteError, STARTER_SYMBOLS, binanceKlinesUrl, binanceUrl, decodeBinance, decodeKlines, decodeYahoo,
  isCryptoPair, normalizeSymbol, yahooUrl,
} from "./quotes.js";

export const INTERVAL_MS = 60_000;
// Stock requests are spaced at least this far apart.
export const YAHOO_SPACING_MS = 1_000;

export function readPreferences(value) {
  // Nothing saved yet: a starter list, until the first edit saves the person's own.
  if (value === undefined || value === null) return { version: 1, symbols: [...STARTER_SYMBOLS], paused: false };
  const saved = typeof value === "object" ? value : null;
  const symbols = [];
  if (saved?.version === 1 && Array.isArray(saved.symbols)) {
    for (const raw of saved.symbols) {
      if (typeof raw !== "string") continue;
      try {
        const symbol = normalizeSymbol(raw);
        if (!symbols.includes(symbol)) symbols.push(symbol);
      } catch { /* Skip one bad entry, not the whole list. */ }
    }
  }
  return { version: 1, symbols, paused: saved?.version === 1 && saved.paused === true };
}

/**
 * host: {
 *   load(): unknown, save(preferences): void          // the saved watchlist
 *   fetch(url): Promise<{ status, ok, text }>          // GET, body read
 *   now(): number, sleep(ms): Promise<void>
 *   changed(): void                                    // redraw, from the loop only
 * }
 */
export class Watchlist {
  constructor(host, intervalMs = INTERVAL_MS) {
    this.host = host;
    this.intervalMs = intervalMs;
    this.preferences = readPreferences(host.load());
    this.quotes = {};
    this.errors = {};
    this.message = "";
    this.loading = false;
    this.retryAt = 0;
    this.rateFailures = 0;
    this.revision = 0;
    this.stopped = false;
    this.manual = false;
    this.dirty = true;
    this.lastYahooAt = -Infinity;
    this.wake = null;
  }

  // Edits are synchronous (the store is Herdr's shared state) and return a short notice.
  edit(change) {
    const preferences = readPreferences(this.host.load());
    const message = change(preferences);
    this.host.save(preferences);
    this.adopt(preferences);
    this.revision++;
    this.dirty = true;
    this.poke();
    return message;
  }

  add(input) {
    const symbol = normalizeSymbol(input);
    return this.edit((p) => {
      if (p.symbols.includes(symbol)) return `${symbol} is already on your watchlist.`;
      p.symbols.push(symbol);
      return `Added ${symbol}.`;
    });
  }

  remove(symbol) {
    return this.edit((p) => {
      if (!p.symbols.includes(symbol)) return `${symbol} is not on your watchlist.`;
      p.symbols = p.symbols.filter((s) => s !== symbol);
      return `Removed ${symbol}.`;
    });
  }

  pause(paused) {
    return this.edit((p) => {
      p.paused = paused;
      return paused ? "Automatic refresh paused." : "Automatic refresh resumed.";
    });
  }

  /** One round now, also while paused; a Yahoo cooldown still holds for stocks. */
  refreshNow() {
    this.manual = true;
    this.poke();
  }

  stop() {
    this.stopped = true;
    this.revision++;
    this.poke();
  }

  poke() {
    const wake = this.wake;
    this.wake = null;
    wake?.();
  }

  /** Picks up another copy's edit of the shared list at once (the main view calls it on render). */
  sync() {
    const preferences = readPreferences(this.host.load());
    if (JSON.stringify(preferences) === JSON.stringify(this.preferences)) return false;
    this.adopt(preferences);
    this.revision++;
    this.dirty = true;
    this.poke();
    return true;
  }

  adopt(preferences) {
    this.preferences = preferences;
    const keep = new Set(preferences.symbols);
    for (const record of [this.quotes, this.errors]) {
      for (const key of Object.keys(record)) if (!keep.has(key)) delete record[key];
    }
  }

  /** Runs until stop(). Each round starts the interval after the previous one ends. */
  async run() {
    while (!this.stopped) {
      const manual = this.manual;
      this.manual = false;
      this.dirty = false;
      // Another copy may have edited the shared list.
      this.adopt(readPreferences(this.host.load()));
      const due = manual || (!this.preferences.paused && this.preferences.symbols.length > 0);
      if (due) await this.round(manual);
      if (this.stopped) return;
      this.host.changed();
      if (this.manual || this.dirty) continue;
      const idle = this.preferences.paused || !this.preferences.symbols.length;
      await new Promise((resolve) => {
        this.wake = resolve;
        if (!idle) this.host.sleep(this.intervalMs).then(resolve);
      });
      this.wake = null;
    }
  }

  async round(manual) {
    const revision = this.revision;
    const current = () => !this.stopped && revision === this.revision;
    const symbols = this.preferences.symbols;
    this.loading = true;
    this.message = "";
    this.host.changed();
    try {
      const pairs = symbols.filter(isCryptoPair);
      for (let i = 0; i < pairs.length && current(); i += BINANCE_BATCH) {
        await this.crypto(pairs.slice(i, i + BINANCE_BATCH), current);
      }
      const tickers = symbols.filter((s) => !isCryptoPair(s));
      if (!tickers.length || !current()) return;
      if (this.host.now() < this.retryAt) {
        // Pairs keep their cadence through a Yahoo cooldown; stocks wait it out.
        this.message = `Yahoo rate limited requests. Retry after ${Math.ceil((this.retryAt - this.host.now()) / 1000)}s.`;
        return;
      }
      for (const [index, symbol] of tickers.entries()) {
        const wait = YAHOO_SPACING_MS - (this.host.now() - this.lastYahooAt);
        if (wait > 0) await this.host.sleep(wait);
        if (!current()) return;
        this.lastYahooAt = this.host.now();
        try {
          const response = await this.get(yahooUrl(symbol));
          if (!current()) return;
          this.quotes[symbol] = decodeYahoo(symbol, response, this.host.now());
          delete this.errors[symbol];
        } catch (error) {
          if (!current()) return;
          this.errors[symbol] = error instanceof QuoteError ? error.message : "Could not reach Yahoo Finance.";
          if (error instanceof QuoteError && error.retryAfterMs !== undefined) {
            this.rateFailures++;
            const backoff = Math.min(900_000, 60_000 * 2 ** Math.min(this.rateFailures - 1, 4));
            this.retryAt = this.host.now() + Math.max(backoff, error.retryAfterMs);
            this.message = "Yahoo rate limited requests. Automatic retries are delayed.";
            for (const rest of tickers.slice(index + 1)) this.errors[rest] = "Refresh deferred: Yahoo rate limited requests.";
            return;
          }
        }
        this.host.changed();
      }
      if (current()) { this.rateFailures = 0; this.retryAt = 0; }
    } finally {
      this.loading = false;
    }
  }

  async get(url) {
    const response = await this.host.fetch(url);
    return { status: response.status, ok: response.ok, text: await response.text() };
  }

  /** One request per batch; an unknown pair fails the batch, so then ask pair by pair. */
  async crypto(pairs, current) {
    const fetchPairs = async (list) => {
      const response = await this.get(binanceUrl(list));
      if (!current()) return;
      const quotes = decodeBinance(list, response, this.host.now());
      for (const pair of list) {
        if (quotes[pair]) {
          // Keep the last line until a new one arrives.
          quotes[pair].series = this.quotes[pair]?.series ?? [];
          this.quotes[pair] = quotes[pair];
          delete this.errors[pair];
        } else this.errors[pair] = "Binance returned no quote for this pair.";
      }
    };
    const fail = (list, error) => {
      for (const pair of list) this.errors[pair] = error instanceof QuoteError ? error.message : "Could not reach Binance.";
    };
    try {
      await fetchPairs(pairs);
    } catch (error) {
      if (!current()) return;
      if (error instanceof QuoteError && error.invalidSymbol && pairs.length > 1) {
        for (const pair of pairs) {
          if (!current()) return;
          try { await fetchPairs([pair]); } catch (cause) { if (current()) fail([pair], cause); }
        }
      } else fail(pairs, error);
    }
    if (!current()) return;
    this.host.changed();
    // The 24-hour line, one request a pair; a failure only leaves the line as it was.
    for (const pair of pairs) {
      if (!current()) return;
      if (!this.quotes[pair]) continue;
      try {
        const series = decodeKlines(await this.get(binanceKlinesUrl(pair)));
        if (current() && this.quotes[pair]) this.quotes[pair].series = series;
      } catch { /* The quote itself is fine. */ }
    }
    if (current()) this.host.changed();
  }
}
