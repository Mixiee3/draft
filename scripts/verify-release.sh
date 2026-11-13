#!/bin/bash
# Verifies a built Draft.app (and its archive): signature, hardened runtime, entitlements, Gatekeeper,
# stapled notarization ticket, Info.plist and archive integrity. Exit 1 on a failure; notarization
# and Gatekeeper are reported (not failed) for ad-hoc development builds.
# Usage: scripts/verify-release.sh [Draft.app] [archive.zip]
set -uo pipefail
APP=${1:-build/Draft.app}; ZIP=${2:-}
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }; note() { echo "NOTE $1"; }
codesign --verify --deep --strict "$APP" 2>/dev/null && ok "code signature is valid (deep, strict)" || bad "code signature"
FLAGS=$(codesign -dvv "$APP" 2>&1)
echo "$FLAGS" | grep -q "flags=.*runtime" && ok "hardened runtime" || bad "hardened runtime flag missing"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "audio-input" && ok "entitlements present" || bad "entitlements"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "allow-jit\|allow-unsigned-executable-memory\|disable-library-validation" && bad "unexpected hardened-runtime exception" || ok "no JIT/unsigned-memory/library-validation exceptions"
TEAM=$(echo "$FLAGS" | grep '^TeamIdentifier=' | cut -d= -f2)
PL="$APP/Contents/Info.plist"
V=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PL"); B=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PL"); C=$(/usr/libexec/PlistBuddy -c "Print :DraftChannel" "$PL" 2>/dev/null)
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]] && ok "version $V (build $B, channel $C)" || bad "version '$V' is not semantic"
[[ "$B" =~ ^[0-9]+$ ]] && ok "numeric build number" || bad "build number '$B'"
if [ "$TEAM" = "not set" ] || [ -z "$TEAM" ]; then
  note "ad-hoc signature: not distributable, not notarized"
elif ! echo "$FLAGS" | grep -q "Authority=Developer ID Application"; then
  note "signed by $(echo "$FLAGS" | grep -m1 ^Authority= | cut -d= -f2) (team $TEAM): runs on this Mac, not distributable, not notarized"
else
  spctl -a -t exec -vv "$APP" 2>&1 | grep -q "accepted" && ok "Gatekeeper accepts it (Developer ID, notarized)" || bad "Gatekeeper rejects it"
  xcrun stapler validate "$APP" >/dev/null 2>&1 && ok "notarization ticket stapled" || bad "no stapled notarization ticket"
fi
/usr/libexec/PlistBuddy -c "Print :DraftUpdatePublicKey" "$PL" >/dev/null 2>&1 && ok "update public key embedded" || note "no update key: this build can't install updates"
# It has to start: the hardened runtime refuses frameworks signed by another team (or ad hoc).
T=$(mktemp -d); DRAFT_DATA_DIR=$T/vault DRAFT_AUTOMATION=launch-check DRAFT_OUT=$T/out "$APP/Contents/MacOS/Draft" >$T/log 2>&1 & P=$!
for _ in 1 2 3 4 5 6 7 8; do kill -0 $P 2>/dev/null || break; sleep 1; done
if kill -0 $P 2>/dev/null || [ -f "$T/vault/library.json" ]; then ok "app launches and opens a throwaway vault"; else bad "app doesn't launch: $(grep -m1 -o 'Reason:.*\|not valid.*' $T/log | cut -c1-160)"; fi
kill $P 2>/dev/null; wait $P 2>/dev/null; rm -rf "${T:?}"
if [ -n "$ZIP" ]; then
  T=$(mktemp -d); ditto -x -k "$ZIP" "$T" && [ -d "$T/Draft.app" ] && codesign --verify --deep --strict "$T/Draft.app" && ok "archive extracts to a valid signed app" || bad "archive"
  rm -rf "${T:?}"
fi
[ $fail = 0 ] && echo "RELEASE VERIFY PASSED" || echo "RELEASE VERIFY FAILED"
exit $fail
