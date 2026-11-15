#!/bin/bash
# Package the signed app as a conventional drag-to-Applications macOS disk image.
# Usage: scripts/make-dmg.sh <Draft.app> <version> <output.dmg>
set -euo pipefail

APP=${1:?usage: make-dmg.sh Draft.app version output.dmg}
VERSION=${2:?usage: make-dmg.sh Draft.app version output.dmg}
OUTPUT=${3:?usage: make-dmg.sh Draft.app version output.dmg}

[ -d "$APP" ] || { echo "App bundle not found: $APP" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT")"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/Draft.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<EOF
Install Draft $VERSION

1. Drag Draft into Applications.
2. Open Draft from Applications.

Draft includes its local runtime; no separate download or account is needed.
Your notes stay on this Mac. The first launch may show a macOS security warning
because this build is not notarized. See the download page for the current steps.
EOF

rm -f "$OUTPUT"
hdiutil create -volname "Draft $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$OUTPUT"
echo "Created $OUTPUT"
