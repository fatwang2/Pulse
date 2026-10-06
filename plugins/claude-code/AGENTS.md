# Pulse Claude Code plugin

- Keep independent Yahoo watchlists and the Pulse Mac view separate. Mac mode
  uses the host's plugin-bundled MCP connection
  and only list_watchlists/get_quotes;
  selection affects CC display only. Never write Mac groups, symbols or trades.
  Preserve the independent list when switching sources. Keep a compact quote
  band and a management panel; do not display charts or mini trends.
- Use Claude Code Mods APIs, not Node imports or direct filesystem/network
  access. Write each host call explicitly in `hooks/register.tsx` so the
  host's static analyzer can inventory it, with each fetch's https origin and
  options written at the call and each command as fixed text.
- Preserve saved watchlists. Pause, removal, exit and reload must discard
  late results and prevent duplicate refresh loops.
- Crypto pairs (`BTC/USDT`) read Binance's public Spot data API only, batched,
  never through Yahoo's spacing or cooldown. A dash symbol stays Yahoo's.
- Respect Yahoo cooldowns. Never present cached data as a newly fetched quote
  or unknown source delay as real time.
- Validate with `claude plugin validate` and exercise behavior with
  `claude plugin test plugins/claude-code` from the repository root.
- Keep generated `.claude-plugin/types/` files out of Git. The MCP token is an
  optional sensitive userConfig field. The terminal opens the host
  configuration dialog with the fixed `/plugin configure pulse-cc`; Desktop,
  which cannot show it, names that command for a terminal session. Never run
  processes, read environment variables, or put credentials in the watchlist
  store, prompt or logs: the directory flags each of them.
- Claude Desktop runs a headless session (`isInteractive` false) and attaches
  later: register `/pulse` unconditionally and start polling on
  `session.attach`. Desktop draws a cell far smaller than a terminal row, so
  spacing branches on `e.surface`; terminal panes also branch on placement.
- Rows show no per-row clock; date a quote only when it is from an earlier day.
- Background `$.mcp.call` reads may be refused by Claude Code's permission check
  (the terminal's default mode, Desktop's auto mode). Tell that apart from
  connection failures and show the refusal and the exact read-only allow rules.
  Never approve the plugin's own calls in `tool.check`: the directory blocks a
  mod that answers allow, and the user's rules decide.
- The plugin is meant for Anthropic's plugin directory: remote MCP URLs must be
  `https://` or a `${user_config.*}` reference, so the local Pulse Mac endpoint
  stays in the `macUrl` option. Keep README images as absolute URLs, the
  README's data disclosures and "What the mod runs" section in step with the
  code (hosts, tool calls, commands, programs), and the plugin folder
  self-contained.
- Leave historical Mac source, the website, Mac workflows, release tags,
  binary assets and the Sparkle feed unchanged.
