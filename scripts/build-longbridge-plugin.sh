#!/usr/bin/env bash
# Build and embed the pinned official Longbridge C SDK plugin.
set -euo pipefail

PLUGIN_NAME="PulseLongbridgePlugin.bundle"
PLUGIN_DESTINATION="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/PlugIns/$PLUGIN_NAME"

SDK_TAG="v4.4.1"
SDK_VERSION="4.4.1"
SDK_COMMIT="bc33287274d69a4617ab7a78167625e44ad83eb2"
PLUGIN_EXECUTABLE="PulseLongbridgePlugin"
PLUGIN_INFO_SOURCE="$SRCROOT/scripts/longbridge-plugin/Info.plist"
OAUTH_TOKEN_PATCH="$SRCROOT/scripts/longbridge-plugin/oauth-token-config.patch"
CACHE_ROOT="$SRCROOT/.build/longbridge-sdk/$SDK_VERSION"
SDK_SOURCE="$CACHE_ROOT/openapi"
# Rust loads proc-macro dylibs while compiling. Keeping these short-lived
# artifacts on the system volume avoids sporadic malformed LINKEDIT reads seen
# when the workspace itself lives on an external APFS volume.
CARGO_TARGET_DIR="${TMPDIR%/}/app.pulse.longbridge-sdk/$SDK_VERSION/target"

BUILD_ARCH="${CURRENT_ARCH:-}"
if [[ -z "$BUILD_ARCH" || "$BUILD_ARCH" == "undefined_arch" ]]; then
  BUILD_ARCH="${NATIVE_ARCH_ACTUAL:-${ARCHS%% *}}"
fi

case "$BUILD_ARCH" in
  arm64)
    RUST_TARGET="aarch64-apple-darwin"
    ;;
  x86_64)
    RUST_TARGET="x86_64-apple-darwin"
    ;;
  *)
    echo "error: unsupported Longbridge plugin architecture: ${BUILD_ARCH:-unset}" >&2
    exit 1
    ;;
esac

for command in git cargo rustup install_name_tool codesign; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: Longbridge SDK plugin requires '$command'." >&2
    exit 1
  fi
done

if ! rustup target list --installed | /usr/bin/grep -qx "$RUST_TARGET"; then
  echo "error: Rust target '$RUST_TARGET' is not installed. Run: rustup target add $RUST_TARGET" >&2
  exit 1
fi

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

# The SDK and Pulse patch are pinned, so avoid asking Cargo to revisit the very
# large workspace on every incremental Xcode build.
PATCH_SHA="$(/usr/bin/shasum -a 256 "$OAUTH_TOKEN_PATCH" | /usr/bin/awk '{print $1}')"
SDK_LIBRARY="$CARGO_TARGET_DIR/$RUST_TARGET/release/liblongbridge_c.dylib"
BUILD_STAMP="$CARGO_TARGET_DIR/$RUST_TARGET/release/.pulse-$SDK_COMMIT-$PATCH_SHA"

# Do not inherit Pulse's macOS 26 deployment target here. With Xcode 27 beta,
# Rust proc-macro dylibs linked at 26 can get malformed chained-fixup metadata.
# The SDK is embedded in a macOS 26 app but can safely target an older runtime.
if [[ ! -f "$SDK_LIBRARY" || ! -f "$BUILD_STAMP" ]]; then
  MACOSX_DEPLOYMENT_TARGET=11.0 CARGO_TARGET_DIR="$CARGO_TARGET_DIR" cargo build \
    --quiet \
    --manifest-path "$SDK_SOURCE/Cargo.toml" \
    --package longbridge-c \
    --release \
    --target "$RUST_TARGET"
  /usr/bin/touch "$BUILD_STAMP"
fi

if [[ ! -f "$SDK_LIBRARY" ]]; then
  echo "error: Longbridge SDK build did not produce $SDK_LIBRARY" >&2
  exit 1
fi

PLUGIN_CONTENTS="$PLUGIN_DESTINATION/Contents"
PLUGIN_BINARY="$PLUGIN_CONTENTS/MacOS/$PLUGIN_EXECUTABLE"

rm -rf "$PLUGIN_DESTINATION"
mkdir -p "$PLUGIN_CONTENTS/MacOS"
/bin/cp "$PLUGIN_INFO_SOURCE" "$PLUGIN_CONTENTS/Info.plist"
/bin/cp "$SDK_LIBRARY" "$PLUGIN_BINARY"
/bin/chmod 755 "$PLUGIN_BINARY"
install_name_tool -id "@loader_path/$PLUGIN_EXECUTABLE" "$PLUGIN_BINARY"
/usr/bin/strip -x "$PLUGIN_BINARY"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi
codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  --timestamp=none \
  "$PLUGIN_DESTINATION"

echo "Longbridge SDK plugin embedded: SDK $SDK_VERSION ($SDK_COMMIT), $RUST_TARGET"
