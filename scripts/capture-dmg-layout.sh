#!/usr/bin/env bash
# Capture the styled DMG layout that release builds reuse.
#
# The installer DMG's icon positions, window bounds, and background reference
# live in the volume's .DS_Store. Finder writes that file, and Finder needs a
# GUI session, so a runner cannot produce one — release-mac.sh copies this
# committed file in instead.
#
# Run this on a Mac after changing assets/dmg/background.tiff or the icon
# positions, passing a DMG whose layout is already correct (a released one, or
# one built locally with assets/dmg/DS_Store temporarily removed so the Finder
# path runs):
#
#   scripts/capture-dmg-layout.sh build/release/dist/Pulse-1.2.3.dmg
#
# Then commit assets/dmg/DS_Store and verify the next DMG opens as expected.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="${1:?usage: capture-dmg-layout.sh <styled.dmg>}"
[[ -f "$DMG" ]] || { echo "error: no such DMG: $DMG" >&2; exit 1; }

MOUNT="$(mktemp -d)"
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT

hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
[[ -f "$MOUNT/.DS_Store" ]] || { echo "error: $DMG carries no .DS_Store; its layout was never applied" >&2; exit 1; }

cp "$MOUNT/.DS_Store" "$ROOT/assets/dmg/DS_Store"
echo "captured $(wc -c < "$ROOT/assets/dmg/DS_Store" | tr -d ' ') bytes into assets/dmg/DS_Store"
