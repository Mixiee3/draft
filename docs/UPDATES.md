# Updates

Built into Draft (`DraftCore/Updates.swift`, `Draft/Updater.swift`), no third-party framework.
Sparkle was evaluated (MIT, EdDSA-signed appcasts, mature): it fits, but it needs a downloaded binary
framework and assumes a Developer ID-signed app. The built-in updater is about 400 lines, uses only
CryptoKit and Apple's tools, and can be tested end to end on this Mac. Switching to Sparkle later
only changes the app side; the release key and the archive signatures stay Ed25519.

## What the person controls

- **Check for Updates…** (Draft menu, Settings › Updates) is the only check unless automatic checks are on.
- **Check automatically** is off by default. Off means Draft makes no update request at all; the updater
  test proves zero requests with it off.
- When an update is found: version, date, size, channel and notes, then **Download** /
  **Remind Me Later** / **Skip This Version**. Downloading shows progress and can be cancelled.
- After download: **Install and Restart**, **Install on Quit** or **Remind Me Later**. Installing within
  a minute of the last keystroke asks first ("You're writing right now").
- No silent install, no telemetry; the request is a plain HTTPS GET of the feed and the archive, with an
  ephemeral session (no cookies, cache or credentials).
- Offline: a manual check says it couldn't reach the server; an automatic one stays quiet.

## Security model

The app trusts one thing: the Ed25519 **release public key** in its Info.plist (`DraftUpdatePublicKey`).

1. **Feed** (`DraftUpdateFeedURL`, HTTPS only): `{"payload": base64(items JSON), "signature": base64}`.
   The signature over the payload must verify with the release key, or the feed is rejected.
2. **Item:** version, build, channel, date, notes, url (HTTPS), size, sha256, Ed25519 signature of the
   archive, minimumSystem, librarySchema, docSchema.
3. **Archive:** size, SHA-256 and the Ed25519 signature must all match before anything is unpacked.
4. **Staged app:** same bundle id, build equal to the item's, `codesign --verify --deep --strict`, the
   same Team ID as the running app, and a development build is refused over stable or beta.
5. **Install:** a detached script waits for Draft to quit, moves the old app to
   `~/Library/Application Support/Draft/Updates/previous`, copies the new one, verifies its signature,
   and relaunches it. If the new app doesn't write its `launched-<build>` marker within 40 s, the old
   app is put back and the next launch says so.

HTTPS protects privacy in transit; the signatures protect integrity even if the server or the
connection is compromised. A stolen release key is the main risk: keep it offline (see RELEASE.md).

Channels: Stable gets stable; Beta gets beta and stable; Development gets everything
([VERSIONING.md](VERSIONING.md)). Compatibility: an item needing a newer macOS can't be downloaded;
an item with a newer schema shows a migration warning, and Draft writes a backup archive before installing it.

## Feed format

```json
{ "payload": "<base64 of [item, …] sorted-keys JSON>", "signature": "<base64 Ed25519 over payload bytes>" }
```

Made with `swift scripts/update-tool.swift feed <key> items.json` (items from `release.sh`).

## Test mode

Only in development builds, only with `DRAFT_UPDATE_TEST=1`. `DRAFT_UPDATE_FEED` (file:// allowed),
`DRAFT_UPDATE_TEST_KEY`, `DRAFT_UPDATE_DIR`, `DRAFT_UPDATE_DEST` (a copy of the app to replace) and
`DRAFT_UPDATE_LAUNCH` (relaunch command). `scripts/update-test.sh` runs: install and restart, install
on quit, remind me later, tampered archive refused, update that doesn't start rolled back, and no
request with automatic checks off — on throwaway vaults and app copies.
