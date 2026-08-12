#!/usr/bin/env python3
import argparse, datetime, hashlib, json, os, pathlib, plistlib, subprocess, tempfile, uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCHEMA = json.load(open(ROOT / "Assets/continuity-evidence-schema.json", encoding="utf-8"))
p = argparse.ArgumentParser(description="Record one exact physical continuity matrix row")
p.add_argument("--row", required=True); p.add_argument("--dmg", required=True); p.add_argument("--app", required=True)
p.add_argument("--device-uid", required=True); p.add_argument("--input-route", required=True)
p.add_argument("--sample-rate", required=True, type=float); p.add_argument("--phase", required=True)
p.add_argument("--notification", action="append", required=True); p.add_argument("--outcome", choices=["Pass","Fail","Blocked"], required=True)
p.add_argument("--audio-disposition", required=True); p.add_argument("--helper-disposition", required=True); p.add_argument("--assertion", required=True)
p.add_argument("--output-dir", default="qualification/evidence"); p.add_argument("--physical", action="store_true")
a=p.parse_args()
if not a.physical: raise SystemExit("refusing record: --physical is required")
if not a.row.replace("-","").isalnum() or a.row.lower()!=a.row or "*" in a.device_uid or "," in a.row: raise SystemExit("refusing generalized evidence")
dmg=pathlib.Path(a.dmg).resolve(); app=pathlib.Path(a.app).resolve()
if dmg.suffix.lower()!=".dmg" or not dmg.is_file(): raise SystemExit("immutable DMG file required")
plist_path=app / "Contents/Info.plist"
if app.suffix.lower()!=".app" or not plist_path.is_file(): raise SystemExit("normal .app bundle with Contents/Info.plist required")
with open(plist_path,"rb") as f: info=plistlib.load(f)
version=info.get("CFBundleShortVersionString"); build=info.get("CFBundleVersion")
if not isinstance(version,str) or not version or not isinstance(build,str) or not build: raise SystemExit("bundle version/build missing")
def digest(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""): h.update(chunk)
    return h.hexdigest()
def command(*args): return subprocess.check_output(args,text=True).strip()
now=datetime.datetime.now(datetime.timezone.utc); expires=now+datetime.timedelta(days=30)
record={"schemaVersion":1,"rowID":a.row,"kind":"physical","appVersion":version,"appBuild":build,"artifactName":dmg.name,"artifactSHA256":digest(dmg),"macOSBuild":command("sw_vers","-buildVersion"),"hardwareIdentifier":command("sysctl","-n","hw.model"),"inputRoute":a.input_route,"inputDeviceUID":a.device_uid,"sampleRate":a.sample_rate,"operationID":str(uuid.uuid4()),"interruptionPhase":a.phase,"notificationsObserved":a.notification,"outcome":a.outcome,"audioDisposition":a.audio_disposition,"helperDisposition":a.helper_disposition,"testerAssertion":a.assertion,"recordedAt":now.isoformat().replace("+00:00","Z"),"expiresAt":expires.isoformat().replace("+00:00","Z")}
if set(record)!=set(SCHEMA["required"]): raise SystemExit("record/schema key mismatch")
os.makedirs(a.output_dir,mode=0o700,exist_ok=True)
name=f"{now.date().isoformat()}-{a.row}-{record['operationID']}.json"; target=os.path.join(a.output_dir,name)
fd,temporary=tempfile.mkstemp(dir=a.output_dir,prefix=".record-",text=True)
with os.fdopen(fd,"w",encoding="utf-8") as f: json.dump(record,f,sort_keys=True,separators=(",",":"))
os.chmod(temporary,0o600); os.replace(temporary,target); print(target)
