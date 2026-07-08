# Distribution

Pulse is distributed outside the Mac App Store:

- GitHub Releases host the downloadable `Pulse.app` update archive.
- Sparkle checks a stable `appcast.xml` asset published on the `appcast` GitHub Release tag.
- Release builds are signed with Developer ID, use hardened runtime, and are notarized with Apple.

The pipeline intentionally keeps all secrets out of the open-source repository.

## One-time setup

Copy the example file and fill in local secrets:

```bash
cp .env.release.example .env.release
```

The values can reuse the same Apple Developer account used by Path:

- `DEVELOPMENT_TEAM`
- `APPLE_SIGNING_IDENTITY`
- `APPLE_API_ISSUER`
- `APPLE_API_KEY`
- `APPLE_API_KEY_PATH`

Do not commit `.env.release`, `.p8` files, signing certificates, or Sparkle private keys.

## Sparkle keys

Sparkle requires an EdDSA key pair:

- `SPARKLE_PUBLIC_ED_KEY` is safe to commit indirectly through Release build settings.
- The private key must stay local or in GitHub Actions secrets.

Generate the key with Sparkle's `generate_keys` tool:

```bash
generate_keys
```

Put the printed public key into `.env.release` as `SPARKLE_PUBLIC_ED_KEY`.

If release automation runs on a different machine, export/import the private key using Sparkle's documented `generate_keys -x` and `generate_keys -f` flow, then point `SPARKLE_PRIVATE_KEY_FILE` at the exported private key.

## Release

Dry-run the signing/notarization pipeline without uploading:

```bash
SKIP_UPLOAD=1 scripts/release-mac.sh
```

Publish a release:

```bash
PULSE_VERSION=0.1.1 scripts/release-mac.sh
```

The script:

1. Generates `Pulse.xcodeproj` from `project.yml`.
2. Archives Release with Developer ID and hardened runtime.
3. Exports, notarizes, and staples `Pulse.app`.
4. Creates `Pulse-<version>.zip`.
5. Generates Sparkle `appcast.xml`.
6. Uploads the zip to `v<version>` on GitHub Releases.
7. Uploads `appcast.xml` to the stable `appcast` GitHub Release tag.

## GitHub Release layout

For version `0.1.1` and repo `owner/Pulse`:

- Download: `https://github.com/owner/Pulse/releases/download/v0.1.1/Pulse-0.1.1.zip`
- Appcast: `https://github.com/owner/Pulse/releases/download/appcast/appcast.xml`

The app's `SUFeedURL` should match the appcast URL.

## Validation

Useful checks after a local release build:

```bash
codesign -dvvv --entitlements :- build/release/export/Pulse.app
codesign --verify --deep --strict --verbose=2 build/release/export/Pulse.app
spctl -a -vv build/release/export/Pulse.app
xcrun stapler validate build/release/export/Pulse.app
```

For a real public release, `spctl` should accept the app and `stapler validate` should pass.
