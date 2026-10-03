# Pulse Claude Code plugin

- Keep independent Yahoo watchlists and the Pulse Mac view separate. Mac mode
  uses the host's configured MCP connection and only list_watchlists/get_quotes;
  selection affects CC display only. Never write Mac groups, symbols or trades.
  Preserve the independent list when switching sources. Keep a compact quote
  band and a management panel; do not display charts or mini trends.
- Use Claude Code Mods APIs, not Node imports or direct filesystem/network
  access. Write each host call explicitly in `hooks/register.tsx` so the
  host's static analyzer can inventory it.
- Preserve saved watchlists. Pause, removal, exit and reload must discard
  late results and prevent duplicate refresh loops.
- Respect Yahoo cooldowns. Never present cached data as a newly fetched quote
  or unknown source delay as real time.
- Validate with `claude plugin validate` and exercise behavior with
  `claude plugin test plugins/claude-code` from the repository root.
- Keep generated `.claude-plugin/types/` files out of Git.
- Leave historical Mac source, the website, Mac workflows, release tags,
  binary assets and the Sparkle feed unchanged.
