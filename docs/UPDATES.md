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

## Three levels of testing (keep them apart)

1. **Local automated tests** (`scripts/update-test.sh`, `UpdatesTests`). Development builds only, with
   `DRAFT_UPDATE_TEST=1` and a `file://` feed on this Mac. They cover install and restart, install on quit,
   remind me later, tampered archive refused, an update that doesn't start rolled back, and no request with
   automatic checks off. They prove the logic, not the network.
2. **Hosted test distribution** (`github.com/Mixiee3/draft-updates`, release tag `preview`, a public repo
   holding only test archives, the signed `feed.json` and release notes). Test-channel *stable* builds
   with the test update key, reached over HTTPS with the production code path (no test mode). Verified on
   14 Nov 2026: a baseline 0.10.0 (205) offered and installed 0.10.1 (206) on a throwaway vault, notes byte-identical,
   and a second check reported no newer update. Test builds are signed with the Apple Development
   identity, so they are not notarized and not for other Macs.
3. **Production public distribution.** Needs a Developer ID certificate, notarization and stapling
   ([RELEASE.md](RELEASE.md)), a stable release channel that you publish, and the update key kept offline.
   Not done yet.

Public-repo rules for hosted tests: no source, no notes, no secrets, no tokens in URLs or the app.
The update key lives outside the repo (`~/Keys/draft-update.key`, mode 0600).

Known limits of the hosted test: the feed is fetched with an ephemeral session, so a private GitHub
release can't be used (it needs authentication the app must not carry). Corrupted and failed-launch
cases are tested locally (level 1), not on the hosted feed. Downloads report progress through a native
download task; a byte-by-byte loop was too slow for a 14 MB archive and was replaced.

## Where the update feed lives (as of 0.11.0)

- The signed feed is `feed.json` on the `preview` release of the public repo `Mixiee3/draft-updates`.
  Public installs read this address because it is baked into each build (`DraftUpdateFeedURL`).
- Each update archive is a public release asset of `Mixiee3/draft` (for example `v0.11.0/Draft-0.11.0.zip`).
  Its item in the feed has an HTTPS URL to that asset.
- To publish a new version: build with `scripts/release.sh`, add its `feed-item.json` (with the archive URL)
  to the feed, sign the feed with `scripts/update-tool.swift feed`, and upload it with `gh release upload --clobber`.
- Caveat: GitHub caches release downloads for a few minutes after an upload, so a fresh feed can take a short while to appear.
- A stable feed host of its own (a dedicated domain or repo) is a later step. Changing the address requires a new build,
  because the address is part of the app.
