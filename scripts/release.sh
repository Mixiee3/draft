#!/bin/bash
# Builds a release of Draft. See docs/RELEASE.md for the secrets and the full procedure.
#
#   DRAFT_CHANNEL=stable|beta            (default stable)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   (required; an "Apple Development" identity works for local
#                 test releases but is not distributable. Ad hoc is refused: the hardened runtime won't load
#                 llama.framework without a Team ID.)
#   NOTARY_PROFILE=<keychain profile from `xcrun notarytool store-credentials`>   (unset → not notarized)
#   UPDATE_KEY=<path to the Ed25519 private key file from scripts/update-tool.swift keygen>   (unset → no update signature)
#   UPDATE_FEED_URL=https://…/feed.json  UPDATE_BASE_URL=https://…/downloads   (written into the app / the feed item)
#
# Output in dist/<version>-<build>/: Draft.app, Draft-<version>.zip, feed-item.json, release-notes.md, SHA256SUMS.
set -euo pipefail
cd "$(dirname "$0")/.."
CHANNEL=${DRAFT_CHANNEL:-stable}
[ "$CHANNEL" = stable ] || [ "$CHANNEL" = beta ] || { echo "DRAFT_CHANNEL must be stable or beta"; exit 1; }
VERSION=$(tr -d ' \n' < VERSION); BUILD=$(git rev-list --count HEAD)
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash changes first: a release is built from a clean tree."; exit 1; }
OUT=dist/$VERSION-$BUILD; rm -rf "$OUT"; mkdir -p "$OUT"
PUBKEY=""; [ -n "${UPDATE_KEY:-}" ] && PUBKEY=$(swift scripts/update-tool.swift pubkey "$UPDATE_KEY")
DRAFT_CHANNEL=$CHANNEL scripts/build-app.sh release >/dev/null
APP=$OUT/Draft.app; ditto build/Draft.app "$APP"
PL="$APP/Contents/Info.plist"
[ -n "$PUBKEY" ] && /usr/libexec/PlistBuddy -c "Add :DraftUpdatePublicKey string $PUBKEY" "$PL"
[ -n "${UPDATE_FEED_URL:-}" ] && /usr/libexec/PlistBuddy -c "Add :DraftUpdateFeedURL string $UPDATE_FEED_URL" "$PL"
IDENT=${SIGN_IDENTITY:?set SIGN_IDENTITY (see docs/RELEASE.md); security find-identity -v -p codesigning lists yours}
# Inside out: frameworks, then the app, with the hardened runtime and a secure timestamp.
TS=--timestamp
for f in "$APP"/Contents/Frameworks/*; do codesign --force --options runtime $TS --sign "$IDENT" "$f"; done
codesign --force --options runtime $TS --entitlements Release/Draft.entitlements --sign "$IDENT" "$APP"
ZIP=$OUT/Draft-$VERSION.zip
ditto -c -k --keepParent "$APP" "$ZIP"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"   # the archive now carries the stapled ticket
  echo "notarized and stapled"
else
  echo "NOT NOTARIZED: set SIGN_IDENTITY (Developer ID) and NOTARY_PROFILE for a distributable build." | tee "$OUT/NOT-NOTARIZED.txt"
fi
cp "Release/notes/$VERSION.md" "$OUT/release-notes.md" 2>/dev/null || echo "# Draft $VERSION" > "$OUT/release-notes.md"
if [ -n "${UPDATE_KEY:-}" ]; then
  LIB=$(grep -o 'librarySchemaVersion = [0-9]*' Sources/DraftCore/Model.swift | grep -o '[0-9]*$'); DOC=$(grep -o 'docSchemaVersion = [0-9]*' Sources/DraftCore/Model.swift | grep -o '[0-9]*$')
  swift scripts/update-tool.swift item "$UPDATE_KEY" "$ZIP" "$VERSION" "$BUILD" "$CHANNEL" "${UPDATE_BASE_URL:-https://example.invalid}/Draft-$VERSION.zip" "$OUT/release-notes.md" "$LIB" "$DOC" > "$OUT/feed-item.json"
fi
(cd "$OUT" && shasum -a 256 "Draft-$VERSION.zip" > SHA256SUMS)
scripts/verify-release.sh "$APP" "$ZIP"
echo "release in $OUT"
