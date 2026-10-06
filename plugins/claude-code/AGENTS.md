# Pulse Claude Code plugin

- Pulse CC has one independent watchlist and no Pulse Mac connection: 0.4.0
  removed the Mac mode, its bundled MCP server and token option. Do not
  reintroduce MCP calls, commands or credentials. Keep a compact quote band and
  a management panel; do not display charts or mini trends.
- Use Claude Code Mods APIs, not Node imports or direct filesystem/network
  access. Write each host call explicitly in `hooks/register.tsx` so the
  host's static analyzer can inventory it, with each fetch's https origin and
  options written at the call and each command as fixed text. Use plain data
  properties, methods and async functions: the directory flags getters,
  Proxies and `then`.
- Preserve saved watchlists. Pause, removal, exit and reload must discard
  late results and prevent duplicate refresh loops.
- Crypto pairs (`BTC/USDT`) read Binance's public Spot data API only, batched,
  never through Yahoo's spacing or cooldown. A dash symbol stays Yahoo's.
- Respect Yahoo cooldowns. Never present cached data as a newly fetched quote
  or unknown source delay as real time.
- Validate with `claude plugin validate` and exercise behavior with
  `claude plugin test plugins/claude-code` from the repository root.
- Keep generated `.claude-plugin/types/` files out of Git. Never run
  processes, read environment variables, or put credentials in the watchlist
  store, prompt or logs: the directory flags each of them.
- Claude Desktop runs a headless session (`isInteractive` false) and attaches
  later: register `/pulse` unconditionally and start polling on
  `session.attach`. Desktop draws a cell far smaller than a terminal row, so
  spacing branches on `e.surface`; terminal panes also branch on placement.
- Rows show no per-row clock; date a quote only when it is from an earlier day.
- Never hook `tool.check` to approve calls: the directory blocks a mod that
  answers allow.
- The plugin is meant for Anthropic's plugin directory. Keep README images as
  absolute URLs, the README's data disclosures and "What the mod runs" section
  in step with the code (hosts, tool calls, commands, programs), and the plugin
  folder self-contained.
- Leave historical Mac source, the website, Mac workflows, release tags,
  binary assets and the Sparkle feed unchanged.
