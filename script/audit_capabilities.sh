#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="${1:-$ROOT/Assets/tk.entitlements}"
APP="${2:-}"

[[ -f "$ENTITLEMENTS" ]] || { echo "missing entitlements" >&2; exit 2; }
keys="$(plutil -convert json -o - "$ENTITLEMENTS" | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin))))')"
[[ "$keys" == "com.apple.security.device.audio-input" ]] || { echo "unexpected entitlement set" >&2; exit 1; }
plutil -extract com.apple.security.device.audio-input raw "$ENTITLEMENTS" | grep -qx true

if [[ -n "$APP" ]]; then
  [[ -d "$APP" ]] || { echo "app bundle missing" >&2; exit 2; }
  ! find "$APP" -type f -name 'whisper-server' -print -quit | grep -q .
  find "$APP" -type f -name 'whisper-cli' -perm -111 -print -quit | grep -q .
  codesign -d --entitlements :- "$APP" >"${TMPDIR:-/tmp}/tk-entitlements-audit.plist" 2>/dev/null
fi

echo "capability audit: PASS"
