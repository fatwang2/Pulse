#!/usr/bin/env bash
# Build, run, debug, or verify the local development app.
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_NAME="Pulse Dev"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
BUNDLE_ID="app.pulse.mac.dev"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

signing_arguments() {
  local identity_line identity certificate_subject team_id

  # A development certificate gives Keychain a stable designated requirement across
  # rebuilds. Discover it locally so no developer identity or private key is committed.
  identity_line="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n '/"Apple Development:/ { p; q; }')"
  if [[ -n "$identity_line" ]]; then
    identity="${identity_line#*\"}"
    identity="${identity%%\"*}"
    certificate_subject="$(security find-certificate -c "$identity" -p 2>/dev/null \
      | /usr/bin/openssl x509 -noout -subject 2>/dev/null || true)"
    team_id="$(printf '%s\n' "$certificate_subject" \
      | sed -nE 's/.*OU[ =]+([A-Z0-9]+).*/\1/p')"
    if [[ -n "$team_id" ]]; then
      printf '%s\0' \
        "CODE_SIGN_STYLE=Manual" \
        "CODE_SIGN_IDENTITY=$identity" \
        "DEVELOPMENT_TEAM=$team_id"
      return
    fi
  fi

  # Contributors without an Apple Development certificate can still build locally.
  # Their ad-hoc build may need Keychain approval again after its code hash changes.
  printf '%s\0' "CODE_SIGN_STYLE=Manual" "CODE_SIGN_IDENTITY=-"
}

SIGNING_ARGS=()
while IFS= read -r -d '' argument; do
  SIGNING_ARGS+=("$argument")
done < <(signing_arguments)

cd "$ROOT_DIR"
xcodegen generate
xcodebuild \
  -project Pulse.xcodeproj \
  -scheme PulseMac \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  TELEMETRYDECK_APP_ID="${TELEMETRYDECK_APP_ID:-}" \
  "${SIGNING_ARGS[@]}" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
