# Pulse Claude Code plugin

- The current MVP uses Yahoo Finance. Integration with the Mac app is planned
  for future versions; Mac integration, MCP, positions and download promotion
  remain outside this MVP's implementation scope. Keep a compact quote band
  and a watchlist management panel; do not display charts or mini trends.
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
