#!/usr/bin/env python3
import argparse, datetime, hashlib, json, os, pathlib, plistlib, re, subprocess, sys, uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]; SCHEMA=json.load(open(ROOT/"Assets/continuity-evidence-schema.json",encoding="utf-8")); REQUIRED=set(SCHEMA["required"])
p=argparse.ArgumentParser(description="Fail-closed compatibility evidence gate"); p.add_argument("--matrix",default="docs/COMPATIBILITY.md"); p.add_argument("--records",default="qualification/evidence"); p.add_argument("--dmg"); p.add_argument("--app"); p.add_argument("--report"); a=p.parse_args()
def cmd(*x): return subprocess.check_output(x,text=True).strip()
def digest(path):
 h=hashlib.sha256()
 with open(path,"rb") as f:
  for chunk in iter(lambda:f.read(1048576),b""): h.update(chunk)
 return h.hexdigest()
def dt(value): return datetime.datetime.fromisoformat(value.replace("Z","+00:00"))
rows=[]; section=""
for line in open(a.matrix,encoding="utf-8"):
 if line.startswith("## "): section=line[3:].strip()
 if not line.startswith("|") or "---" in line or "Status" in line: continue
 cells=[c.strip() for c in line.strip().strip("|").split("|")]; index=next((i for i,c in enumerate(cells) if c in {"Pass","Fail","Blocked","Not run"}),None)
 if index is None: continue
 rid=re.sub(r"[^a-z0-9]+","-",(section+"-"+" | ".join(cells[:index])).lower()).strip("-")
 links=re.findall(r"\[[^]]+\]\(([^)]+\.json)\)",cells[index+1] if index+1<len(cells) else "")
 rows.append({"id":rid,"status":cells[index],"links":links})
records={}; malformed=[]
if os.path.isdir(a.records):
 for name in sorted(os.listdir(a.records)):
  if not name.endswith(".json"): continue
  try:
   value=json.load(open(os.path.join(a.records,name),encoding="utf-8")); records[name]=value
  except Exception: malformed.append(name)
failures=[f"malformed evidence: {x}" for x in malformed]; linked_names=[]; now=datetime.datetime.now(datetime.timezone.utc)
context=None
if a.dmg and a.app:
 try:
  app=pathlib.Path(a.app); info=plistlib.load(open(app/"Contents/Info.plist","rb")); context={"artifactName":pathlib.Path(a.dmg).name,"artifactSHA256":digest(a.dmg),"appVersion":info["CFBundleShortVersionString"],"appBuild":info["CFBundleVersion"],"macOSBuild":cmd("sw_vers","-buildVersion"),"hardwareIdentifier":cmd("sysctl","-n","hw.model")}
 except Exception as e: failures.append(f"artifact context unavailable: {e}")
for row in rows:
 if row["status"]!="Pass": failures.append(f"{row['id']}: {row['status']}"); continue
 if len(row["links"])!=1: failures.append(f"{row['id']}: Record must link exactly one JSON record"); continue
 name=os.path.basename(row["links"][0]); linked_names.append(name); record=records.get(name)
 if record is None: failures.append(f"{row['id']}: linked record missing"); continue
 try:
  if set(record)!=REQUIRED: raise ValueError("malformed keys")
  if record["schemaVersion"]!=1: raise ValueError("future or unsupported schema")
  if record["rowID"]!=row["id"] or record["kind"]!="physical" or record["outcome"]!="Pass": raise ValueError("mismatched record")
  if not re.fullmatch(r"[a-f0-9]{64}",record["artifactSHA256"]): raise ValueError("malformed digest")
  uuid.UUID(record["operationID"])
  if not record["notificationsObserved"] or not record["testerAssertion"].strip(): raise ValueError("missing observations")
  if "*" in record["inputDeviceUID"] or "," in record["rowID"]: raise ValueError("generalized evidence")
  if dt(record["recordedAt"])>now+datetime.timedelta(minutes=5) or dt(record["expiresAt"])<now or dt(record["expiresAt"])-dt(record["recordedAt"])>datetime.timedelta(days=30,minutes=1): raise ValueError("stale or future evidence")
  if context is None: raise ValueError("--dmg and --app required for Pass validation")
  if any(record[k]!=v for k,v in context.items()): raise ValueError("artifact/system mismatch")
 except Exception as e: failures.append(f"{row['id']}: {e}")
for name in records:
 if name not in linked_names: failures.append(f"unlinked evidence: {name}")
if len(linked_names)!=len(set(linked_names)): failures.append("duplicate linked evidence")
report={"schemaVersion":1,"rowCount":len(rows),"qualified":not failures,"failures":failures}
if a.report:
 os.makedirs(os.path.dirname(a.report) or ".",exist_ok=True); temporary=a.report+".tmp"; json.dump(report,open(temporary,"w",encoding="utf-8"),sort_keys=True,indent=2); os.replace(temporary,a.report)
print(json.dumps(report,sort_keys=True)); sys.exit(0 if report["qualified"] else 1)
