#!/usr/bin/env python3
import argparse, datetime, hashlib, json, os, platform, tempfile, uuid

p = argparse.ArgumentParser(description="Record one exact physical continuity matrix row")
p.add_argument("--row", required=True)
p.add_argument("--app", required=True)
p.add_argument("--version", required=True)
p.add_argument("--device-uid", required=True)
p.add_argument("--input-route", required=True)
p.add_argument("--sample-rate", required=True, type=float)
p.add_argument("--phase", required=True)
p.add_argument("--notification", action="append", required=True)
p.add_argument("--outcome", choices=["Pass", "Fail", "Blocked"], required=True)
p.add_argument("--audio-disposition", required=True)
p.add_argument("--helper-disposition", required=True)
p.add_argument("--assertion", required=True)
p.add_argument("--output-dir", default="qualification/evidence")
p.add_argument("--physical", action="store_true", help="assert observations came from real hardware")
a = p.parse_args()
if not a.physical:
    raise SystemExit("refusing record: --physical is required and simulated events cannot become physical evidence")
if "," in a.row or "*" in a.device_uid:
    raise SystemExit("refusing generalized evidence")

def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""): h.update(chunk)
    return h.hexdigest()

record = {
  "schemaVersion": 1, "rowID": a.row, "kind": "physical", "appVersion": a.version,
  "artifactSHA256": digest(a.app), "macOSBuild": platform.version(),
  "hardwareIdentifier": platform.machine(), "inputRoute": a.input_route,
  "inputDeviceUID": a.device_uid, "sampleRate": a.sample_rate,
  "operationID": str(uuid.uuid4()), "interruptionPhase": a.phase,
  "notificationsObserved": a.notification, "outcome": a.outcome,
  "audioDisposition": a.audio_disposition, "helperDisposition": a.helper_disposition,
  "testerAssertion": a.assertion,
  "recordedAt": datetime.datetime.now(datetime.timezone.utc).isoformat()
}
os.makedirs(a.output_dir, mode=0o700, exist_ok=True)
name = f"{datetime.date.today().isoformat()}-{a.row}-{record['operationID']}.json"
target = os.path.join(a.output_dir, name)
fd, temporary = tempfile.mkstemp(dir=a.output_dir, prefix=".record-", text=True)
with os.fdopen(fd, "w") as f: json.dump(record, f, sort_keys=True, separators=(",", ":"))
os.chmod(temporary, 0o600)
os.replace(temporary, target)
print(target)
