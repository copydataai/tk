#!/usr/bin/env python3
import argparse, json, os, re, sys

p = argparse.ArgumentParser(description="Fail-closed compatibility evidence gate")
p.add_argument("--matrix", default="docs/COMPATIBILITY.md")
p.add_argument("--records", default="qualification/evidence")
p.add_argument("--report")
a = p.parse_args()

rows = []
section = ""
with open(a.matrix, encoding="utf-8") as f:
    for line in f:
        if line.startswith("## "): section = line[3:].strip()
        if not line.startswith("|") or "---" in line or "Status" in line: continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 4: continue
        status_index = next((i for i,c in enumerate(cells) if c in {"Pass","Fail","Blocked","Not run"}), None)
        if status_index is None: continue
        identity = " | ".join(cells[:status_index])
        row_id = re.sub(r"[^a-z0-9]+", "-", (section + "-" + identity).lower()).strip("-")
        rows.append({"id": row_id, "status": cells[status_index], "record": cells[status_index + 1] if status_index + 1 < len(cells) else ""})

records = {}
if os.path.isdir(a.records):
    for name in sorted(os.listdir(a.records)):
        if not name.endswith(".json"): continue
        try:
            with open(os.path.join(a.records, name), encoding="utf-8") as f: record = json.load(f)
            records.setdefault(record.get("rowID"), []).append((name, record))
        except Exception: records.setdefault("__malformed__", []).append((name, {}))

failures = []
for row in rows:
    linked = records.get(row["id"], [])
    if row["status"] != "Pass": failures.append(f"{row['id']}: {row['status']}")
    elif len(linked) != 1: failures.append(f"{row['id']}: requires exactly one linked record")
    elif linked[0][1].get("kind") != "physical": failures.append(f"{row['id']}: nonphysical record")
if "__malformed__" in records: failures.append("malformed evidence record")

report = {"rowCount": len(rows), "qualified": not failures, "failures": failures}
if a.report:
    os.makedirs(os.path.dirname(a.report) or ".", exist_ok=True)
    temporary = a.report + ".tmp"
    with open(temporary, "w", encoding="utf-8") as f: json.dump(report, f, sort_keys=True, indent=2)
    os.replace(temporary, a.report)
print(json.dumps(report, sort_keys=True))
sys.exit(0 if report["qualified"] else 1)
