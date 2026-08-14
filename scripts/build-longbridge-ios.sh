#!/usr/bin/env bash
# Build the pinned official Longbridge C SDK as an iOS static library.
#
# Same source, tag, and OAuth-token patch as the macOS plugin
# (build-longbridge-plugin.sh); the difference is the artifact shape. iOS
# forbids loadable plugins, so the SDK is compiled per Rust target with
# `--crate-type staticlib` and linked straight into the app binary. Runs as a
# PulseiOS pre-build phase; LIBRARY_SEARCH_PATHS picks the slice matching the
# active SDK (device vs simulator).
set -euo pipefail

SDK_TAG="v4.4.1"
SDK_VERSION="4.4.1"
SDK_COMMIT="bc33287274d69a4617ab7a78167625e44ad83eb2"
OAUTH_TOKEN_PATCH="$SRCROOT/scripts/longbridge-plugin/oauth-token-config.patch"
CACHE_ROOT="$SRCROOT/.build/longbridge-sdk/$SDK_VERSION"
SDK_SOURCE="$CACHE_ROOT/openapi"
LIB_ROOT="$CACHE_ROOT/ios"
# Rust loads proc-macro dylibs while compiling. Keeping these short-lived
# artifacts on the system volume avoids sporadic malformed LINKEDIT reads seen
# when the workspace itself lives on an external APFS volume.
CARGO_TARGET_DIR="${TMPDIR%/}/app.pulse.longbridge-sdk/$SDK_VERSION/target"

# Xcode strips ~/.cargo/bin from PATH in script phases.
for candidate in "$HOME/.cargo/bin" /opt/homebrew/bin; do
  [[ -d "$candidate" ]] && PATH="$candidate:$PATH"
done
export PATH

for command in git cargo rustup; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: Longbridge iOS SDK build requires '$command'." >&2
    exit 1
  fi
done

case "${PLATFORM_NAME:-iphoneos}" in
  iphonesimulator)
    RUST_TARGETS=("aarch64-apple-ios-sim")
    ;;
  *)
    RUST_TARGETS=("aarch64-apple-ios")
    ;;
esac

mkdir -p "$CACHE_ROOT"
if [[ ! -d "$SDK_SOURCE/.git" ]]; then
  git clone \
    --branch "$SDK_TAG" \
    --depth 1 \
    https://github.com/longbridge/openapi.git \
    "$SDK_SOURCE"
fi

ACTUAL_COMMIT="$(git -C "$SDK_SOURCE" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$SDK_COMMIT" ]]; then
  echo "error: Longbridge SDK commit mismatch: expected $SDK_COMMIT, found $ACTUAL_COMMIT" >&2
  exit 1
fi

if ! /usr/bin/grep -q "lb_config_from_oauth_token" "$SDK_SOURCE/c/src/config.rs"; then
  if ! git -C "$SDK_SOURCE" apply --check "$OAUTH_TOKEN_PATCH"; then
    echo "error: Pulse OAuth token bridge no longer applies cleanly to Longbridge SDK $SDK_VERSION" >&2
    exit 1
  fi
  git -C "$SDK_SOURCE" apply "$OAUTH_TOKEN_PATCH"
fi

PATCH_SHA="$(/usr/bin/shasum -a 256 "$OAUTH_TOKEN_PATCH" | /usr/bin/awk '{print $1}')"

for rust_target in "${RUST_TARGETS[@]}"; do
  if ! rustup target list --installed | /usr/bin/grep -qx "$rust_target"; then
    echo "error: Rust target '$rust_target' is not installed. Run: rustup target add $rust_target" >&2
    exit 1
  fi

  sdk_library="$CARGO_TARGET_DIR/$rust_target/release/liblongbridge_c.a"
  build_stamp="$CARGO_TARGET_DIR/$rust_target/release/.pulse-$SDK_COMMIT-$PATCH_SHA"
  if [[ ! -f "$sdk_library" || ! -f "$build_stamp" ]]; then
    IPHONEOS_DEPLOYMENT_TARGET=17.0 CARGO_TARGET_DIR="$CARGO_TARGET_DIR" cargo rustc \
      --quiet \
      --manifest-path "$SDK_SOURCE/c/Cargo.toml" \
      --package longbridge-c \
      --release \
      --target "$rust_target" \
      --crate-type staticlib
    /usr/bin/touch "$build_stamp"
  fi

  if [[ ! -f "$sdk_library" ]]; then
    echo "error: Longbridge SDK build did not produce $sdk_library" >&2
    exit 1
  fi

  mkdir -p "$LIB_ROOT/$rust_target"
  if ! /usr/bin/cmp -s "$sdk_library" "$LIB_ROOT/$rust_target/liblongbridge_c.a"; then
    /bin/cp "$sdk_library" "$LIB_ROOT/$rust_target/liblongbridge_c.a"
  fi
done

echo "Longbridge iOS SDK ready: ${RUST_TARGETS[*]}"
