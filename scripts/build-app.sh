#!/bin/bash
# Builds Draft.app (release) into ./build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Draft
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Draft"
APP=build/Draft.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Draft"
BINDIR="$(dirname "$BIN")"
for b in "$BINDIR"/*.bundle; do cp -R "$b" "$APP/Contents/Resources/"; done
mkdir -p "$APP/Contents/Frameworks"
cp -R "$BINDIR/llama.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Draft" 2>/dev/null || true
for t in THIRD_PARTY_NOTICES.md; do [ -f "$t" ] && cp "$t" "$APP/Contents/Resources/"; done
if [ ! -f build/AppIcon.icns ]; then
  TMP=$(mktemp -d)
  swift scripts/make-icon.swift "$TMP/icon.png"
  mkdir -p "$TMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Draft</string>
  <key>CFBundleDisplayName</key><string>Draft</string>
  <key>CFBundleIdentifier</key><string>org.draftnotes.Draft</string>
  <key>CFBundleExecutable</key><string>Draft</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.5.1</string>
  <key>NSMicrophoneUsageDescription</key><string>Draft listens only while you hold the Assistant's microphone button, to turn your speech into text on this Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Draft uses Apple's on-device speech recognition for Assistant dictation. Your voice is not sent to a server.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Draft shows your calendar events next to daily notes when you turn this on in Settings. Events are read on this Mac only and never changed.</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>org.draftnotes.Draft.link</string>
    <key>CFBundleURLSchemes</key><array><string>draft</string></array>
  </dict></array>
  <key>NSHumanReadableCopyright</key><string>Free and open source. Your notes stay on your Mac.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
