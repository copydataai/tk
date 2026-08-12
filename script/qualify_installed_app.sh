#!/usr/bin/env bash
set -euo pipefail

DMG="${1:?usage: qualify_installed_app.sh path/to/tk.dmg}"
APP="${2:-/Applications/tk.app}"
[[ -f "$DMG" && -d "$APP" ]] || { echo "mounted artifact and drag-installed app required" >&2; exit 2; }
shasum -a 256 -c "$DMG.sha256"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
[[ "$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)" == "${TK_VERSION:?set TK_VERSION}" ]]
find "$APP" -type f -name whisper-cli -perm -111 -print -quit | grep -q .
! find "$APP" -type f -name whisper-server -print -quit | grep -q .
[[ -f "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md" ]]
[[ -f "$APP/Contents/Resources/uninstall.json" ]]
"$(dirname "$0")/audit_capabilities.sh" "$(dirname "$0")/../Assets/tk.entitlements" "$APP"
"$(dirname "$0")/qualify_compatibility.py"
