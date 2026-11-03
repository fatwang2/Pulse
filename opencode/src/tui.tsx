// Pulse for opencode: a stock and crypto watchlist in the session sidebar, plus a
// one-line quote band. Each ticker shows its price, today's line and its change;
// click one for its day. Stocks and indices come from Yahoo Finance, crypto pairs
// (BTC/USDT) from Binance's public Spot data. Edit the list with /pulse-add and
// /pulse-remove; it is kept in opencode's own storage.
//
// One module for both opencode lines: v1 (opencode-ai 1.15+) calls `tui`, v2
// (@opencode/cli 2.x) calls `setup`. Both share the views in view.tsx.
import { ID } from "./view.tsx"
import { tui } from "./v1.tsx"
import { setup } from "./v2.tsx"

const plugin = { id: ID, tui, setup }
export default plugin
