#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
VERSION="${TK_VERSION:-0.1.0}"
mkdir -p "$DIST"

if [[ -n "${TK_SIGNING_IDENTITY:-}" && -n "${TK_NOTARY_PROFILE:-}" ]]; then
  "$ROOT/script/build_and_run.sh" --release
  release_status="signed-notarized-candidate"
else
  "$ROOT/script/build_and_run.sh" --dmg
  release_status="unsigned-development-only"
fi

APP="$DIST/tk.app"
DMG="$DIST/tk-$VERSION.dmg"
"$ROOT/script/audit_capabilities.sh" "$ROOT/Assets/tk.entitlements" "$APP"
find "$APP" -type f -name whisper-cli -perm -111 -print -quit | grep -q .
! find "$APP" -type f -name whisper-server -print -quit | grep -q .

shasum -a 256 "$DMG" >"$DMG.sha256"
find "$APP/Contents/Resources" -type f -print0 | sort -z | xargs -0 shasum -a 256 >"$DIST/bundled-files.sha256"
python3 - "$ROOT" "$DIST" "$release_status" <<'PY'
import datetime,json,os,subprocess,sys
root,dist,status=sys.argv[1:]
resolved=json.load(open(os.path.join(root,"Package.resolved")))
sbom={"format":"tk-sbom-1","packages":resolved.get("pins",[]),"licenses":"Assets/THIRD_PARTY_NOTICES.md"}
provenance={"format":"tk-provenance-1","status":status,"commit":subprocess.check_output(["git","rev-parse","HEAD"],cwd=root,text=True).strip(),"createdAt":datetime.datetime.now(datetime.timezone.utc).isoformat(),"credentialsLogged":False}
for name,value in [("sbom.json",sbom),("provenance.json",provenance)]:
  with open(os.path.join(dist,name),"w") as f: json.dump(value,f,sort_keys=True,indent=2)
PY

[[ "$release_status" == "signed-notarized-candidate" ]] || {
  echo "UNSIGNED DEVELOPMENT ARTIFACT: release qualification is blocked" >&2
  exit 3
}
