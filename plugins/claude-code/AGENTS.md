# Pulse Claude Code plugin

- Keep independent Yahoo watchlists and the Pulse Mac view separate. Mac mode
  uses the host's plugin-bundled MCP connection
  and only list_watchlists/get_quotes;
  selection affects CC display only. Never write Mac groups, symbols or trades.
  Preserve the independent list when switching sources. Keep a compact quote
  band and a management panel; do not display charts or mini trends.
- Use Claude Code Mods APIs, not Node imports or direct filesystem/network
  access. Write each host call explicitly in `hooks/register.tsx` so the
  host's static analyzer can inventory it.
- Preserve saved watchlists. Pause, removal, exit and reload must discard
  late results and prevent duplicate refresh loops.
- Crypto pairs (`BTC/USDT`) read Binance's public Spot data API only, batched,
  never through Yahoo's spacing or cooldown. A dash symbol stays Yahoo's.
- Respect Yahoo cooldowns. Never present cached data as a newly fetched quote
  or unknown source delay as real time.
- Validate with `claude plugin validate` and exercise behavior with
  `claude plugin test plugins/claude-code` from the repository root.
- Keep generated `.claude-plugin/types/` files out of Git. The MCP token is an
  optional sensitive userConfig field. The terminal uses the host configuration
  dialog; Desktop, which cannot show it, passes the token on stdin to
  `claude plugin configure --values-stdin`. Never put credentials in the
  watchlist store, prompt, logs or process arguments.
- Claude Desktop runs a headless session (`isInteractive` false) and attaches
  later: register `/pulse` unconditionally and start polling on
  `session.attach`. Desktop draws a cell far smaller than a terminal row, so
  spacing branches on `e.surface`; terminal panes also branch on placement.
- Rows show no per-row clock; date a quote only when it is from an earlier day.
- Background `$.mcp.call` reads may be refused by Claude Code's permission check
  (Desktop's auto mode). Tell that apart from connection failures, show the
  refusal and the exact read-only allow rules; never weaken checks for writes.
- Leave historical Mac source, the website, Mac workflows, release tags,
  binary assets and the Sparkle feed unchanged.
