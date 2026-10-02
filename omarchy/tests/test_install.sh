#!/usr/bin/env bash
# install.sh, exercised against a throwaway XDG_CONFIG_HOME with omarchy and
# omarchy-shell stubbed out. It checks the two things that actually go wrong:
# where the symlink lands, and whether a real watchlist survives a reinstall.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/omarchy" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$work/bin/omarchy"

export PATH="$work/bin:$PATH"
export XDG_CONFIG_HOME="$work/config"

plugin_link="$XDG_CONFIG_HOME/omarchy/plugins/pulse.omarchy"
watchlist="$XDG_CONFIG_HOME/omarchy/pulse/watchlist.json"

bash "$root/install.sh" --no-restart >/dev/null

[[ -L "$plugin_link" ]] || { echo "FAIL: no symlink at $plugin_link" >&2; exit 1; }
[[ "$(readlink -f "$plugin_link")" == "$root" ]] || { echo "FAIL: symlink points elsewhere" >&2; exit 1; }
[[ -f "$watchlist" ]] || { echo "FAIL: watchlist was not seeded" >&2; exit 1; }

# The watchlist is the one thing here the user owns. A reinstall must not touch it.
printf '{"version":1,"symbols":["MINE"]}' > "$watchlist"
bash "$root/install.sh" --no-restart >/dev/null
grep -q MINE "$watchlist" || { echo "FAIL: reinstall overwrote the user's watchlist" >&2; exit 1; }

# A stale real directory in the plugin slot is moved out of the plugins tree
# entirely — a backup left beside it would be a second plugin with the same id.
rm "$plugin_link"
mkdir -p "$plugin_link"
touch "$plugin_link/manifest.json"
bash "$root/install.sh" --no-restart >/dev/null
[[ -L "$plugin_link" ]] || { echo "FAIL: stale directory was not replaced" >&2; exit 1; }
backups=$(find "$XDG_CONFIG_HOME/omarchy/plugin-backups" -maxdepth 1 -name 'pulse.omarchy.bak.*' | wc -l)
[[ "$backups" -eq 1 ]] || { echo "FAIL: expected one backup outside the plugins tree, found $backups" >&2; exit 1; }
[[ -z "$(find "$XDG_CONFIG_HOME/omarchy/plugins" -maxdepth 1 -name '*.bak.*')" ]] \
  || { echo "FAIL: a backup was left inside the plugins tree" >&2; exit 1; }

# The example watchlist has to parse, and every symbol in it has to resolve —
# it is the first thing a new install shows.
node -e '
const fs = require("fs")
const SymbolID = require(process.argv[1] + "/tests/qmljs.js").load("SymbolID.js")
const config = JSON.parse(fs.readFileSync(process.argv[1] + "/watchlist.example.json", "utf8"))
const symbols = (config.lists || [{symbols: config.symbols}]).flatMap(l => l.symbols)
for (const raw of symbols) {
  if (!SymbolID.parse(raw)) { console.error("FAIL: example watchlist has an unresolvable symbol: " + raw); process.exit(1) }
}
if (!SymbolID.parse(config.pinnedSymbol)) { console.error("FAIL: example pinnedSymbol does not resolve"); process.exit(1) }
' "$root"

echo "install checks passed"
