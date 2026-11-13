# Releasing Draft

`scripts/release.sh` builds, signs, notarizes, staples, archives and verifies a release in
`dist/<version>-<build>/`. `scripts/verify-release.sh` checks any built app on its own.

## Version and build

- Version: the `VERSION` file (semantic, see [VERSIONING.md](VERSIONING.md)).
- Build number: `git rev-list --count HEAD`. It only grows, so the updater can compare builds.
- Channel: `DRAFT_CHANNEL=stable|beta` for releases. Local builds (`scripts/build-app.sh`) are
  `development` and can never be offered to or install over stable or beta.
- A release is built from a clean tree, so the commit in `DraftCommit` (Info.plist) is the source.

## Required secrets

None of these are in the repository, and `.gitignore` refuses the usual key files. Keep them in the
login Keychain or in CI secrets.

| Secret | Used for | Where it lives |
|---|---|---|
| Developer ID Application certificate + private key | `SIGN_IDENTITY`, code signing | Keychain (CI: base64 `.p12` + password, imported into a temporary keychain) |
| Notary credentials: Apple ID + app-specific password + Team ID, **or** an App Store Connect API key (`.p8`, key ID, issuer ID) | `NOTARY_PROFILE`, made once with `xcrun notarytool store-credentials <profile>` | Keychain profile |
| Ed25519 update signing key | `UPDATE_KEY`, signs each update archive and the feed | A file with mode 0600 outside the repo (`swift scripts/update-tool.swift keygen <file>`); back it up offline. Losing it means existing installs can't verify updates. |

Not secret: `UPDATE_FEED_URL` (HTTPS feed address embedded in the app), `UPDATE_BASE_URL` (where archives are hosted).

## Steps

```bash
DRAFT_CHANNEL=stable \
SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE=draft-notary \
UPDATE_KEY=~/Keys/draft-update.key \
UPDATE_FEED_URL=https://example.org/draft/stable/feed.json \
UPDATE_BASE_URL=https://example.org/draft/downloads \
scripts/release.sh
```

1. Builds with the channel, version and build number in Info.plist, and embeds the update public key and feed URL.
2. Signs `llama.framework`, then the app, with the hardened runtime, a secure timestamp and
   `Release/Draft.entitlements` (microphone and calendar only; no JIT, unsigned memory or disabled library validation).
3. Zips, submits to notarization (`notarytool submit --wait`), staples the ticket and zips again.
4. Writes `release-notes.md` from `Release/notes/<version>.md` (the same text the feed item carries),
   `feed-item.json` (signed by the update key) and `SHA256SUMS`.
5. Runs `scripts/verify-release.sh`: deep strict signature, hardened runtime, entitlements, Gatekeeper,
   stapled ticket, semantic version, archive integrity.
6. Publish: add `feed-item.json` to the channel's items list, then
   `swift scripts/update-tool.swift feed <key> items.json > feed.json`, upload the archive, then the feed.

Without `SIGN_IDENTITY` the app is signed ad hoc and without `NOTARY_PROFILE` it isn't notarized;
the script says `NOT NOTARIZED` and writes `NOT-NOTARIZED.txt` so such a build is never mistaken for a release.

## Current state (v0.10.0)

This Mac has only an Apple Development certificate, not Developer ID, and no notary credentials, so
releases made here are signed ad hoc with the hardened runtime and are **not notarized**. Notarization
and stapling run unchanged once the secrets above exist.
