#!/usr/bin/env bash
# Source regression checks. These guard the two rules that are easy to break by
# accident and impossible to see in a screenshot on one theme.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
failed=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failed=1
}

# 1. No hard-coded colors in QML.
#
# Every color must come from the active Omarchy theme, or be derived from an
# inherited one with alpha. A literal hex is a color that looks right on the
# theme it was written against and wrong on the other forty.
qml_files=$(find . -name '*.qml' -not -path './.git/*')
for file in $qml_files; do
  # ThemePalette parses hex out of the theme's own colors.toml; the pattern
  # there is matching data, not painting with it.
  if [[ "$file" == "./ThemePalette.qml" ]]; then continue
  fi
  if grep -nE '(color|Color)[^:]*:\s*"#[0-9A-Fa-f]{3,8}"' "$file"; then
    fail "$file assigns a literal hex color"
  fi
done

# PulseLogo carries a fallback for use outside a themed context; it must still
# be overridden by every caller rather than relied on.
if ! grep -q 'foregroundColor: root.foreground' Panel.qml; then
  fail "Panel.qml does not pass the bar foreground into the Pulse mark"
fi

# 2. Direction color is never the only indicator.
#
# A rise and a fall must be separable without color, so the percent text always
# carries its sign.
if ! grep -q 'value >= 0 ? "+" : ""' Model.js; then
  fail "Model.js no longer signs percentages"
fi

# 3. Flat is not a rise.
if ! grep -q 'changePercent < 0 ? fallColor : textColor' components/WatchlistRow.qml; then
  fail "components/WatchlistRow.qml no longer gives a flat row the neutral foreground"
fi

# 4. A market badge is always the display label, never the raw market code.
#
#    `sh` and `sz` both read CN, `kr` and `kq` both read KR. Uppercasing the
#    market instead is the easy mistake, and it puts one instrument under two
#    different badges on two screens of the same panel.
if grep -rn '\.market\.toUpperCase()' --include='*.qml' .; then
  fail "a QML file badges a raw market code instead of Market.displayLabel()"
fi

# 5. The manifest id and the install path agree; a mismatch installs a plugin
#    the shell will never load.
manifest_id=$(node -p 'require("./manifest.json").id')
install_id=$(sed -n 's/^plugin_id="\(.*\)"$/\1/p' install.sh)
if [[ "$manifest_id" != "$install_id" ]]; then
  fail "manifest.json id ($manifest_id) does not match install.sh ($install_id)"
fi

if [[ $failed -eq 0 ]]; then
  printf 'source checks passed\n'
fi
exit $failed
