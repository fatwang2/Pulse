#!/usr/bin/env bash
# Build, run, debug, or verify the local development app.
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
BUNDLE_ID="app.pulse.mac.dev"
CONFIGURATION="Debug"
APP_NAME="Pulse Dev"
RELEASE_BUILD=0

# Use a complete Xcode for project builds without changing the machine-wide
# xcode-select setting. CommandLineTools alone exposes xcodebuild but cannot run it.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [[ ! -d "$ACTIVE_DEVELOPER_DIR/Platforms/MacOSX.platform" ]]; then
    for XCODE_DEVELOPER_DIR in \
      "/Applications/Xcode.app/Contents/Developer" \
      "/Applications/Xcode-beta.app/Contents/Developer"
    do
      if [[ -x "$XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
        export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
        break
      fi
    done
  fi
fi

case "$MODE" in
  --release|release|--release-verify|--release-sdk|release-sdk|--release-sdk-verify|--release-settings-persistence-selftest|--release-sdk-live-selftest|--release-sdk-watchlist-selftest|--release-sdk-stability-selftest)
    CONFIGURATION="Release"
    APP_NAME="Pulse"
    BUNDLE_ID="app.pulse.mac"
    RELEASE_BUILD=1
    ;;
esac

APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ "$RELEASE_BUILD" == "1" ]]; then
  # Avoid running Debug and Release simultaneously with the same Longbridge
  # credentials, which could consume multiple quote connections.
  pkill -x "Pulse" >/dev/null 2>&1 || true
  pkill -x "Pulse Dev" >/dev/null 2>&1 || true
else
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

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

XCODE_ARGS=(
  "ENABLE_USER_SCRIPT_SANDBOXING=NO"
)
if [[ "$RELEASE_BUILD" == "1" ]]; then
  XCODE_ARGS+=(
    "ENABLE_HARDENED_RUNTIME=YES"
  )
fi

xcodebuild \
  -project Pulse.xcodeproj \
  -scheme PulseMac \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  TELEMETRYDECK_APP_ID="${TELEMETRYDECK_APP_ID:-}" \
  "${SIGNING_ARGS[@]}" \
  "${XCODE_ARGS[@]}" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --release|release|--release-sdk|release-sdk)
    open_app
    ;;
  --release-verify|--release-sdk-verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --release-sdk-live-selftest)
    "$APP_BINARY" --longbridge-sdk-live-selftest
    ;;
  --release-sdk-watchlist-selftest)
    "$APP_BINARY" --longbridge-sdk-watchlist-selftest
    ;;
  --release-sdk-stability-selftest)
    "$APP_BINARY" --longbridge-sdk-stability-selftest
    ;;
  --release-settings-persistence-selftest)
    "$APP_BINARY" --settings-persistence-selftest
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
  --longbridge-plugin-state-selftest)
    "$APP_BINARY" --longbridge-plugin-state-selftest
    ;;
  --longbridge-plugin-selftest)
    "$APP_BINARY" --longbridge-plugin-selftest
    ;;
  --longbridge-sdk-live-selftest)
    "$APP_BINARY" --longbridge-sdk-live-selftest
    ;;
  --longbridge-sdk-watchlist-selftest)
    "$APP_BINARY" --longbridge-sdk-watchlist-selftest
    ;;
  --longbridge-sdk-stability-selftest)
    "$APP_BINARY" --longbridge-sdk-stability-selftest
    ;;
  --settings-persistence-selftest)
    "$APP_BINARY" --settings-persistence-selftest
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--release|--release-verify|--settings-persistence-selftest|--release-settings-persistence-selftest|--release-sdk-live-selftest|--release-sdk-watchlist-selftest|--release-sdk-stability-selftest|--longbridge-plugin-state-selftest|--longbridge-plugin-selftest|--longbridge-sdk-live-selftest|--longbridge-sdk-watchlist-selftest|--longbridge-sdk-stability-selftest]" >&2
    exit 2
    ;;
esac
