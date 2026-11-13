#!/bin/bash
# Updater test mode, end to end, without publishing anything: a copy of build/Draft.app plays the
# installed app, a patched copy (next build) is the update, signed with a throwaway Ed25519 key and
# served from a file:// feed. Throwaway vault. Scenarios: install and relaunch, install on quit,
# remind me later, tampered archive refused, update that doesn't start is rolled back, no request
# when automatic checks are off. Usage: scripts/update-test.sh  (after scripts/build-app.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
[ -d build/Draft.app ] || { echo "build/Draft.app missing: run scripts/build-app.sh"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "${T:?}"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
PL=build/Draft.app/Contents/Info.plist
OLDV=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $PL); OLDB=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" $PL)
NEWB=$((OLDB + 1)); NEWV="$OLDV-test"
swift scripts/update-tool.swift keygen "$T/key" >/dev/null; PUB=$(swift scripts/update-tool.swift pubkey "$T/key")
mkdir -p "$T/new" "$T/bad"
# The update: same app, next build, re-signed like local builds.
ditto build/Draft.app "$T/new/Draft.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEWV" -c "Set :CFBundleVersion $NEWB" "$T/new/Draft.app/Contents/Info.plist"
codesign --force --deep --sign - "$T/new/Draft.app" >/dev/null 2>&1
(cd "$T/new" && ditto -c -k --keepParent Draft.app update.zip)
echo "- Test update" > "$T/notes.md"
item() { swift scripts/update-tool.swift item "$T/key" "$1" "$NEWV" $NEWB stable "file://$1" "$T/notes.md" 2 1; }
feed() { echo "[$(item "$1")]" > "$T/items.json"; swift scripts/update-tool.swift feed "$T/key" "$T/items.json" > "$2"; }
feed "$T/new/update.zip" "$T/feed.json"
# Tampered: signed, then one byte changed.
cp "$T/new/update.zip" "$T/bad/update.zip"; feed "$T/bad/update.zip" "$T/bad-feed.json"
printf 'X' | dd of="$T/bad/update.zip" bs=1 seek=2000 conv=notrunc 2>/dev/null

# run <name> <feed> <mode> <launch command>: fresh installed copy, throwaway vault and work folder.
run() {
  local D=$T/$1; mkdir -p "$D/Applications" "$D/out"; ditto build/Draft.app "$D/Applications/Draft.app"
  DRAFT_DATA_DIR=$D/vault DRAFT_OUT=$D/out DRAFT_AUTOMATION=${5:-update-e2e} DRAFT_UPDATE_MODE=$3 \
  DRAFT_UPDATE_TEST=1 DRAFT_UPDATE_FEED=file://$2 DRAFT_UPDATE_TEST_KEY=$PUB DRAFT_UPDATE_DIR=$D/work \
  DRAFT_UPDATE_DEST=$D/Applications/Draft.app DRAFT_UPDATE_LAUNCH="$4" \
    "$D/Applications/Draft.app/Contents/MacOS/Draft" >"$D/log" 2>&1 &
  local P=$!; for _ in $(seq 1 600); do kill -0 $P 2>/dev/null || break; sleep 0.1; done
  kill -0 $P 2>/dev/null && { echo "FAIL $1: the app didn't quit within 60 s"; fail=1; kill $P; }
  for _ in $(seq 1 300); do grep -q "installed\|rolling back\|failed" "$D/work/install.log" 2>/dev/null && break; [ -f "$D/work/install.sh" ] || break; sleep 0.1; done
  sleep 1
}
ver() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$T/$1/Applications/Draft.app/Contents/Info.plist"; }
j() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$T/$1/out/$2" "$3" 2>/dev/null; }

L='DRAFT_AUTOMATION=update-after DRAFT_OUT=$(dirname "$DEST")/../out "$DEST/Contents/MacOS/Draft"'
run restart "$T/feed.json" restart "$L"
[ "$(j restart update-e2e.json testMode)" = True ] && ok "test mode on in a development build" || bad "test mode off"
[ "$(j restart update-e2e.json offered)" = "$NEWV ($NEWB)" ] && ok "check offers $NEWV ($NEWB)" || bad "offer: $(j restart update-e2e.json phase)"
[ "$(ver restart)" = $NEWB ] && ok "install and restart replaced the app" || bad "app not replaced: $(tail -3 $T/restart/work/install.log 2>/dev/null)"
for _ in $(seq 1 100); do [ -f "$T/restart/out/update-after.json" ] && break; sleep 0.1; done; sleep 0.3
[ "$(j restart update-after.json build)" = $NEWB ] && ok "the new build launched and confirmed" || bad "new build didn't report"
[ -d "$T/restart/work/previous/Draft.app" ] && ok "previous app kept for rollback" || bad "no backup of the previous app"

run quit "$T/feed.json" quit true
[ "$(ver quit)" = $NEWB ] && ok "install on quit replaced the app after quitting" || bad "install on quit: $(tail -3 $T/quit/work/install.log 2>/dev/null)"
[ ! -f "$T/quit/out/update-after.json" ] && ok "install on quit didn't relaunch" || bad "relaunched"

run later "$T/feed.json" later true
[ "$(ver later)" = "$OLDB" ] && [ ! -f "$T/later/work/install.sh" ] && ok "remind me later leaves the app alone" || bad "later changed the app"

run tampered "$T/bad-feed.json" restart true
P=$(j tampered update-e2e.json phase)
[ "$(ver tampered)" = "$OLDB" ] && [[ "$P" == failed* ]] && ok "tampered archive refused ($P)" || bad "tampered: phase $P, build $(ver tampered)"

run broken "$T/feed.json" restart true   # the new app never starts
[ "$(ver broken)" = "$OLDB" ] && [ -f "$T/broken/work/rolled-back" ] && ok "update that didn't start rolled back to build $OLDB" || bad "rollback: build $(ver broken), $(tail -2 $T/broken/work/install.log 2>/dev/null)"

run disabled "$T/feed.json" restart true update-disabled
[ "$(j disabled update-disabled.json fetches)" = 0 ] && [ "$(j disabled update-disabled.json updateChecks)" = False ] && ok "automatic checks off: no request" || bad "requests while disabled: $(j disabled update-disabled.json fetches)"

[ $fail = 0 ] && echo "UPDATE TEST PASSED" || echo "UPDATE TEST FAILED"
exit $fail
