#!/usr/bin/env bash
# Developer ID + Sparkle + GitHub Releases pipeline for Pulse.
#
# Flow:
#   xcodegen -> archive (Release, Developer ID, hardened runtime)
#   -> exportArchive -> notarytool submit/wait -> staple
#   -> Pulse.app.zip for Sparkle -> Pulse.dmg for first install
#   -> Sparkle appcast -> GitHub Releases upload
#
# Required local configuration:
#   cp .env.release.example .env.release
#   edit Apple, GitHub, and Sparkle values
#
# Useful dry run:
#   SKIP_UPLOAD=1 scripts/release-mac.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${PULSE_RELEASE_ENV:-$ROOT/.env.release}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: missing $ENV_FILE (copy .env.release.example first)" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

: "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM is required}"
: "${APPLE_SIGNING_IDENTITY:?APPLE_SIGNING_IDENTITY is required}"
: "${APPLE_API_ISSUER:?APPLE_API_ISSUER is required}"
: "${APPLE_API_KEY:?APPLE_API_KEY is required}"
: "${APPLE_API_KEY_PATH:?APPLE_API_KEY_PATH is required}"
: "${GH_REPO:?GH_REPO is required, for example owner/Pulse}"
: "${SPARKLE_FEED_URL:?SPARKLE_FEED_URL is required}"
: "${SPARKLE_PUBLIC_ED_KEY:?SPARKLE_PUBLIC_ED_KEY is required}"

if [[ -z "${TELEMETRYDECK_APP_ID:-}" ]]; then
  echo "warning: TELEMETRYDECK_APP_ID is empty; anonymous usage analytics will be disabled" >&2
fi

[[ -f "$APPLE_API_KEY_PATH" ]] || { echo "error: missing APPLE_API_KEY_PATH: $APPLE_API_KEY_PATH" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "error: xcodegen is required" >&2; exit 1; }
command -v gh >/dev/null || { echo "error: GitHub CLI (gh) is required" >&2; exit 1; }

VERSION="${PULSE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' PulseMac/Info.plist 2>/dev/null || echo 0.1.0)}"
if [[ "$VERSION" == "\$(MARKETING_VERSION)" ]]; then
  # The generated Info.plist stores the build-setting placeholder. Read the
  # macOS target's own block, and fail instead of guessing: the old fallback
  # was "0.1.0" — a tag that already exists, whose assets the upload step
  # would have clobbered with a build of something else entirely.
  VERSION="$(python3 - <<'PYVERSION'
import re
import sys
from pathlib import Path

text = Path("project.yml").read_text()
target = re.split(r"^  PulseMac:\s*$", text, flags=re.M)
if len(target) < 2:
    sys.exit("no PulseMac target in project.yml")
match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', target[1])
if not match:
    sys.exit("PulseMac declares no MARKETING_VERSION")
print(match.group(1))
PYVERSION
)" || { echo "error: could not resolve the macOS marketing version" >&2; exit 1; }
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: resolved version is not a release version: $VERSION" >&2
  exit 1
fi
BUILD_NUMBER="${PULSE_BUILD_NUMBER:-$(date +%s)}"
TAG="${PULSE_TAG:-v$VERSION}"
RELEASE_NOTES_FILE="${PULSE_RELEASE_NOTES_FILE:-$ROOT/.github/release-notes/$VERSION.md}"

# Missing notes usually mean the version resolved to something nobody wrote
# notes for, which is worth catching before an hour of notarization.
if [[ ! -f "$RELEASE_NOTES_FILE" && "${ALLOW_MISSING_RELEASE_NOTES:-0}" != "1" ]]; then
  echo "error: no release notes at $RELEASE_NOTES_FILE" >&2
  echo "Write them, or set ALLOW_MISSING_RELEASE_NOTES=1 to publish without them." >&2
  exit 1
fi

echo "==> Releasing Pulse $VERSION as $TAG"

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "error: build number must be a positive integer, found: $BUILD_NUMBER" >&2
  exit 1
fi

if [[ "${SKIP_BUILD_NUMBER_CHECK:-0}" != "1" ]]; then
  echo "==> Checking build number against published appcast"
  if ! PUBLISHED_BUILD="$(
    curl --fail --silent --show-error --location --max-time 20 "$SPARKLE_FEED_URL" \
      | /usr/bin/python3 -c '
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.stdin).getroot()
version = root.find(".//{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
if version is None or not (version.text or "").strip():
    raise SystemExit("published appcast has no sparkle:version")
print(version.text.strip())
'
  )"; then
    echo "error: unable to read the current build number from $SPARKLE_FEED_URL" >&2
    exit 1
  fi

  if [[ ! "$PUBLISHED_BUILD" =~ ^[0-9]+$ ]]; then
    echo "error: published appcast build is not an integer: $PUBLISHED_BUILD" >&2
    exit 1
  fi

  if (( 10#$BUILD_NUMBER <= 10#$PUBLISHED_BUILD )); then
    echo "error: build $BUILD_NUMBER must be greater than published build $PUBLISHED_BUILD" >&2
    echo "Set PULSE_BUILD_NUMBER to a larger value. Use SKIP_BUILD_NUMBER_CHECK=1 only for appcast recovery." >&2
    exit 1
  fi
else
  echo "warning: SKIP_BUILD_NUMBER_CHECK=1; build monotonicity was not verified" >&2
fi

BUILD_DIR="$ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Pulse.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
ENTITLEMENTS_PATH="$BUILD_DIR/Release.entitlements"
DIST_DIR="$BUILD_DIR/dist"
APPCAST_DIR="$BUILD_DIR/appcast"

rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR" "$DIST_DIR" "$APPCAST_DIR"

cat > "$ENTITLEMENTS_PATH" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <!-- The Longbridge OAuth flow answers the browser redirect on a loopback listener -->
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>app.pulse.mac-spks</string>
        <string>app.pulse.mac-spki</string>
    </array>
</dict>
</plist>
PLIST

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "==> Generating Xcode project"
xcodegen generate >/dev/null

echo "==> Resolving Swift packages"
xcodebuild -quiet -resolvePackageDependencies \
  -project Pulse.xcodeproj \
  -scheme PulseMac

find_sparkle_tool() {
  local tool="$1"
  local candidates=()
  if [[ -n "${SPARKLE_BIN:-}" ]]; then
    candidates+=("$SPARKLE_BIN/$tool")
  fi
  candidates+=(
    "$ROOT/vendor/Sparkle/bin/$tool"
    "$ROOT/build/Sparkle/bin/$tool"
    "/Applications/Sparkle.app/Contents/Resources/$tool"
  )
  while IFS= read -r path; do
    candidates+=("$path")
  done < <(
    find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool" -type f 2>/dev/null
    find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/checkouts/Sparkle/$tool" -type f 2>/dev/null
  )
  for path in "${candidates[@]}"; do
    if [[ -x "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

create_dmg() {
  local source_dir="$1"
  local output_path="$2"
  local volume_name="$3"

  rm -f "$output_path"
  if command -v diskutil >/dev/null && diskutil image create from -help >/dev/null 2>&1; then
    diskutil image create from \
      --format UDZO \
      --volumeName "$volume_name" \
      "$source_dir" \
      "$output_path" >/dev/null
  else
    hdiutil create \
      -volname "$volume_name" \
      -srcfolder "$source_dir" \
      -ov \
      -format UDZO \
      "$output_path" >/dev/null
  fi
}

# The installer DMG with the branded background and drag-to-Applications layout.
# Finder view options live in the volume's .DS_Store, so this works on a
# read-write image first and compresses afterwards. If Finder scripting fails
# (headless session, automation permission), the DMG ships unstyled rather than
# blocking the release.
# Regenerate the background with: swift scripts/generate-dmg-background.swift
create_installer_dmg() {
  local source_dir="$1"
  local output_path="$2"
  local volume_name="$3"
  local background="$ROOT/assets/dmg/background.tiff"

  if [[ ! -f "$background" ]]; then
    echo "warning: assets/dmg/background.tiff missing; creating plain DMG" >&2
    create_dmg "$source_dir" "$output_path" "$volume_name"
    return 0
  fi

  mkdir -p "$source_dir/.background"
  cp "$background" "$source_dir/.background/background.tiff"

  local rw_path="${output_path%.dmg}-rw.dmg"
  rm -f "$rw_path" "$output_path"
  hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$source_dir" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    "$rw_path" >/dev/null

  local device
  device="$(hdiutil attach -readwrite -noverify -noautoopen "$rw_path" | awk '/\/dev\/disk/ {print $1; exit}')"

  # Window bounds: 600x400 content (matching the background) plus the title bar.
  # Icon positions pair with the arrow endpoints drawn into the background.
  if ! osascript <<EOF
tell application "Finder"
  tell disk "$volume_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 140, 1000, 568}
    set view_options to the icon view options of container window
    set arrangement of view_options to not arranged
    set icon size of view_options to 112
    set text size of view_options to 12
    set background picture of view_options to file ".background:background.tiff"
    set position of item "Pulse.app" of container window to {150, 205}
    set position of item "Applications" of container window to {450, 205}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
  then
    echo "warning: Finder layout scripting failed; the DMG ships without it" >&2
  fi

  sync
  hdiutil detach "$device" >/dev/null
  hdiutil convert "$rw_path" -format UDZO -o "$output_path" >/dev/null
  rm -f "$rw_path"
}

GENERATE_APPCAST="$(find_sparkle_tool generate_appcast || true)"
GENERATE_KEYS="$(find_sparkle_tool generate_keys || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  cat >&2 <<'EOF'
error: Sparkle generate_appcast was not found.

Install or download Sparkle's release tools, then set:
  SPARKLE_BIN=/path/to/Sparkle/bin

The app runtime uses SwiftPM, but Sparkle's appcast CLI is a separate release tool.
EOF
  exit 1
fi

if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  [[ -f "$SPARKLE_PRIVATE_KEY_FILE" ]] || { echo "error: missing SPARKLE_PRIVATE_KEY_FILE" >&2; exit 1; }
  if [[ -n "$GENERATE_KEYS" ]]; then
    "$GENERATE_KEYS" -f "$SPARKLE_PRIVATE_KEY_FILE" >/dev/null
  else
    echo "warning: generate_keys not found; assuming Sparkle private key is already in keychain" >&2
  fi
fi

echo "==> Archiving Pulse ${VERSION} (${BUILD_NUMBER})"
xcodebuild -quiet archive \
  -project Pulse.xcodeproj \
  -scheme PulseMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$APPLE_SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS_PATH" \
  SPARKLE_FEED_URL="$SPARKLE_FEED_URL" \
  SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  TELEMETRYDECK_APP_ID="${TELEMETRYDECK_APP_ID:-}"

echo "==> Exporting Developer ID archive"
xcodebuild -quiet -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR"

APP_PATH="$EXPORT_DIR/Pulse.app"
[[ -d "$APP_PATH" ]] || { echo "error: exported Pulse.app not found" >&2; exit 1; }

echo "==> Verifying executable architectures"
APP_BINARY="$APP_PATH/Contents/MacOS/Pulse"
PLUGIN_BINARY="$APP_PATH/Contents/PlugIns/PulseLongbridgePlugin.bundle/Contents/MacOS/PulseLongbridgePlugin"
[[ -f "$APP_BINARY" ]] || { echo "error: exported Pulse executable not found" >&2; exit 1; }
[[ -f "$PLUGIN_BINARY" ]] || { echo "error: exported Longbridge plugin not found" >&2; exit 1; }
APP_ARCHITECTURES="$(lipo -archs "$APP_BINARY" | tr ' ' '\n' | sort | tr '\n' ' ')"
PLUGIN_ARCHITECTURES="$(lipo -archs "$PLUGIN_BINARY" | tr ' ' '\n' | sort | tr '\n' ' ')"
if [[ "$APP_ARCHITECTURES" != "$PLUGIN_ARCHITECTURES" ]]; then
  echo "error: architecture mismatch: Pulse [$APP_ARCHITECTURES], Longbridge plugin [$PLUGIN_ARCHITECTURES]" >&2
  exit 1
fi
echo "    Pulse and Longbridge plugin: $APP_ARCHITECTURES"

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ZIP_FOR_NOTARY="$BUILD_DIR/Pulse.app.zip"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_FOR_NOTARY"

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  echo "==> Notarizing"
  xcrun notarytool submit "$ZIP_FOR_NOTARY" \
    --key "$APPLE_API_KEY_PATH" \
    --key-id "$APPLE_API_KEY" \
    --issuer "$APPLE_API_ISSUER" \
    --wait

  echo "==> Stapling"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
else
  echo "warning: SKIP_NOTARIZE=1; do not publish this build" >&2
fi

ZIP_NAME="Pulse-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
echo "==> Creating update archive $ZIP_NAME"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
cp "$ZIP_PATH" "$APPCAST_DIR/$ZIP_NAME"

DMG_NAME="Pulse-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_STAGE="$BUILD_DIR/dmg-stage"
echo "==> Creating first-install disk image $DMG_NAME"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
/usr/bin/ditto "$APP_PATH" "$DMG_STAGE/Pulse.app"
ln -s /Applications "$DMG_STAGE/Applications"
create_installer_dmg "$DMG_STAGE" "$DMG_PATH" "Pulse"

echo "==> Signing disk image"
codesign --force \
  --sign "$APPLE_SIGNING_IDENTITY" \
  --timestamp \
  --options runtime \
  "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  echo "==> Notarizing disk image"
  xcrun notarytool submit "$DMG_PATH" \
    --key "$APPLE_API_KEY_PATH" \
    --key-id "$APPLE_API_KEY" \
    --issuer "$APPLE_API_ISSUER" \
    --wait

  echo "==> Stapling disk image"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

DOWNLOAD_PREFIX="https://github.com/${GH_REPO}/releases/download/${TAG}/"
echo "==> Generating Sparkle appcast"
"$GENERATE_APPCAST" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  "$APPCAST_DIR"

if [[ "${SKIP_UPLOAD:-0}" == "1" ]]; then
  echo "warning: SKIP_UPLOAD=1; artifacts are in $DIST_DIR and $APPCAST_DIR" >&2
  exit 0
fi

echo "==> Uploading GitHub Release assets"
if gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ZIP_PATH" "$DMG_PATH" --repo "$GH_REPO" --clobber
else
  if [[ -f "$RELEASE_NOTES_FILE" ]]; then
    gh release create "$TAG" "$ZIP_PATH" "$DMG_PATH" \
      --repo "$GH_REPO" \
      --title "Pulse ${VERSION}" \
      --notes-file "$RELEASE_NOTES_FILE"
  else
    gh release create "$TAG" "$ZIP_PATH" "$DMG_PATH" \
      --repo "$GH_REPO" \
      --title "Pulse ${VERSION}" \
      --notes "Pulse ${VERSION}

For first-time installation, download Pulse-${VERSION}.dmg and drag Pulse to Applications.
The zip asset is used by Sparkle automatic updates."
  fi
fi

echo "==> Publishing stable Sparkle appcast asset"
if ! gh release view appcast --repo "$GH_REPO" >/dev/null 2>&1; then
  gh release create appcast \
    --repo "$GH_REPO" \
    --title "Sparkle appcast" \
    --notes "Stable appcast feed for Pulse automatic updates"
fi
gh release upload appcast "$APPCAST_DIR/appcast.xml" --repo "$GH_REPO" --clobber

echo ""
echo "Done:"
echo "  Release: https://github.com/${GH_REPO}/releases/tag/${TAG}"
echo "  Appcast: ${SPARKLE_FEED_URL}"
echo "  Installer: $DMG_PATH"
