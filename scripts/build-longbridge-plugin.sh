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

BUILD_ARCHS=()
if [[ -n "${CURRENT_ARCH:-}" && "$CURRENT_ARCH" != "undefined_arch" ]]; then
  BUILD_ARCHS+=("$CURRENT_ARCH")
else
  for build_arch in ${ARCHS:-${NATIVE_ARCH_ACTUAL:-}}; do
    BUILD_ARCHS+=("$build_arch")
  done
fi

if [[ ${#BUILD_ARCHS[@]} -eq 0 ]]; then
  echo "error: Longbridge plugin build architectures are unset" >&2
  exit 1
fi

rust_target_for_arch() {
  case "$1" in
    arm64)
      printf '%s\n' "aarch64-apple-darwin"
      ;;
    x86_64)
      printf '%s\n' "x86_64-apple-darwin"
      ;;
    *)
      echo "error: unsupported Longbridge plugin architecture: $1" >&2
      return 1
      ;;
  esac
}

for command in git cargo rustup lipo install_name_tool codesign; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: Longbridge SDK plugin requires '$command'." >&2
    exit 1
  fi
done

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
SDK_LIBRARIES=()
RUST_TARGETS=()

# Do not inherit Pulse's macOS 26 deployment target here. With Xcode 27 beta,
# Rust proc-macro dylibs linked at 26 can get malformed chained-fixup metadata.
# The SDK is embedded in a macOS 26 app but can safely target an older runtime.
for build_arch in "${BUILD_ARCHS[@]}"; do
  rust_target="$(rust_target_for_arch "$build_arch")"
  if ! rustup target list --installed | /usr/bin/grep -qx "$rust_target"; then
    echo "error: Rust target '$rust_target' is not installed. Run: rustup target add $rust_target" >&2
    exit 1
  fi

  sdk_library="$CARGO_TARGET_DIR/$rust_target/release/liblongbridge_c.dylib"
  build_stamp="$CARGO_TARGET_DIR/$rust_target/release/.pulse-$SDK_COMMIT-$PATCH_SHA"
  if [[ ! -f "$sdk_library" || ! -f "$build_stamp" ]]; then
    MACOSX_DEPLOYMENT_TARGET=11.0 CARGO_TARGET_DIR="$CARGO_TARGET_DIR" cargo build \
      --quiet \
      --manifest-path "$SDK_SOURCE/Cargo.toml" \
      --package longbridge-c \
      --release \
      --target "$rust_target"
    /usr/bin/touch "$build_stamp"
  fi

  if [[ ! -f "$sdk_library" ]]; then
    echo "error: Longbridge SDK build did not produce $sdk_library" >&2
    exit 1
  fi
  SDK_LIBRARIES+=("$sdk_library")
  RUST_TARGETS+=("$rust_target")
done

PLUGIN_CONTENTS="$PLUGIN_DESTINATION/Contents"
PLUGIN_BINARY="$PLUGIN_CONTENTS/MacOS/$PLUGIN_EXECUTABLE"

rm -rf "$PLUGIN_DESTINATION"
mkdir -p "$PLUGIN_CONTENTS/MacOS"
/bin/cp "$PLUGIN_INFO_SOURCE" "$PLUGIN_CONTENTS/Info.plist"
if [[ ${#SDK_LIBRARIES[@]} -eq 1 ]]; then
  /bin/cp "${SDK_LIBRARIES[0]}" "$PLUGIN_BINARY"
else
  lipo -create "${SDK_LIBRARIES[@]}" -output "$PLUGIN_BINARY"
fi
/bin/chmod 755 "$PLUGIN_BINARY"
install_name_tool -id "@loader_path/$PLUGIN_EXECUTABLE" "$PLUGIN_BINARY"
/usr/bin/strip -x "$PLUGIN_BINARY"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi
SIGN_OPTIONS=(--timestamp=none)
if [[ ( "${CONFIGURATION:-}" == "Release" || "${ENABLE_HARDENED_RUNTIME:-}" == "YES" ) \
  && "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_OPTIONS=(--timestamp --options=runtime)
fi
codesign \
  --force \
  --sign "$SIGN_IDENTITY" \
  "${SIGN_OPTIONS[@]}" \
  "$PLUGIN_DESTINATION"

echo "Longbridge SDK plugin embedded: SDK $SDK_VERSION ($SDK_COMMIT), ${RUST_TARGETS[*]}"
