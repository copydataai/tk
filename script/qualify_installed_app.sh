#!/usr/bin/env bash
set -euo pipefail

DMG="${1:?usage: qualify_installed_app.sh path/to/tk.dmg}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$DMG" && -f "$DMG.sha256" ]] || { echo "DMG and matching .sha256 required" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tk-installed-qualification.XXXXXX")"
MOUNT="$WORK/mount"; INSTALL="$WORK/install"; READY="$WORK/readiness.json"; mkdir -p "$MOUNT" "$INSTALL"
device=""; cleanup() { [[ -z "$device" ]] || hdiutil detach "$device" -force >/dev/null 2>&1 || true; rm -rf "$WORK"; }; trap cleanup EXIT
(cd "$(dirname "$DMG")" && shasum -a 256 -c "$(basename "$DMG").sha256")
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
attach="$(hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT" -plist)"
device="$(printf '%s' "$attach" | plutil -extract system-entities raw -o - - | awk '/dev-entry/ {getline; print; exit}' | sed -E 's/.*<string>([^<]+).*/\1/')"
SOURCE_APP="$(find "$MOUNT" -maxdepth 2 -type d -name '*.app' -print -quit)"; [[ -n "$SOURCE_APP" ]] || { echo "mounted DMG contains no app" >&2; exit 3; }
APP="$INSTALL/$(basename "$SOURCE_APP")"; ditto "$SOURCE_APP" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"; codesign -d --entitlements :- "$APP" >/dev/null
xcrun stapler validate "$APP"; spctl --assess --type execute --verbose=2 "$APP"
INFO="$APP/Contents/Info.plist"; VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$INFO")"; BUILD="$(plutil -extract CFBundleVersion raw -o - "$INFO")"; [[ -n "$VERSION" && -n "$BUILD" ]]
RES="$APP/Contents/Resources"; [[ -x "$RES/whisper-cli" && ! -e "$RES/whisper-server" && -f "$RES/THIRD_PARTY_NOTICES.md" ]]
python3 - "$RES" <<'PY'
import json,pathlib,sys
r=pathlib.Path(sys.argv[1])
def load(name): return json.load(open(r/name,encoding="utf-8"))
uninstall=load("uninstall.json"); rollback=load("rollback.json"); network=load("network-policy.json")
if uninstall!={"schemaVersion":1,"applicationSupport":["~/Library/Application Support/tk"],"installedApp":"tk.app","userInitiated":True}: raise SystemExit("invalid uninstall schema")
if rollback.get("schemaVersion")!=1 or rollback.get("strategy")!="install-prior-notarized-dmg" or rollback.get("preservesPendingText") is not True: raise SystemExit("invalid rollback schema")
if network!={"schemaVersion":1,"offlineOperation":True,"runtimeDownloadsRequired":False,"residentListener":False}: raise SystemExit("offline/network declaration failed")
PY
[[ -f "$(dirname "$DMG")/sbom.json" && -f "$(dirname "$DMG")/provenance.json" ]]
python3 - "$(dirname "$DMG")" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); sbom=json.load(open(p/"sbom.json")); provenance=json.load(open(p/"provenance.json"))
if sbom.get("format")!="tk-sbom-1" or not isinstance(sbom.get("packages"),list) or not sbom.get("licenses"): raise SystemExit("invalid SBOM")
if provenance.get("format")!="tk-provenance-1" or provenance.get("credentialsLogged") is not False or not provenance.get("commit") or not provenance.get("createdAt"): raise SystemExit("invalid provenance")
PY
"$ROOT/script/audit_capabilities.sh" "$ROOT/Assets/tk.entitlements" "$APP"
TK_QUALIFICATION_READY_FILE="$READY" open -W -n "$APP"
[[ -f "$READY" ]]; python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r=={"schemaVersion":1,"ready":True,"residentListener":False}' "$READY"
! pgrep -f "$APP/Contents/MacOS" >/dev/null
! lsof -nP -a -c tk -iTCP -sTCP:LISTEN 2>/dev/null | grep -F "$APP" >/dev/null
"$ROOT/script/qualify_compatibility.py" --dmg "$DMG" --app "$APP"
echo "installed artifact predicates passed for $VERSION ($BUILD)"
