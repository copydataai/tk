#!/usr/bin/env bash
set -euo pipefail

if [[ "${TK_RUN_HEAVY_BENCHMARK:-0}" != "1" ]]; then
  echo "SKIP: set TK_RUN_HEAVY_BENCHMARK=1 to benchmark the bundled helper" >&2
  exit 77
fi

APP="${1:-dist/tk.app}"
PROFILE_ID="${TK_BENCHMARK_PROFILE_ID:-dictation.balanced}"
THRESHOLDS="${TK_BENCHMARK_THRESHOLDS:?set TK_BENCHMARK_THRESHOLDS to the versioned threshold JSON}"
RECEIPTS="${TK_BENCHMARK_RECEIPTS:-dist/inference-receipts.jsonl}"
HELPER="$APP/Contents/Resources/whisper-cli"
MODEL="$APP/Contents/Resources/models/ggml-large-v3-turbo-q5_0.bin"
VAD="$APP/Contents/Resources/models/ggml-silero-v6.2.0.bin"
HARDWARE="$(sysctl -n hw.model)"
[[ -x "$HELPER" && -f "$MODEL" && -f "$VAD" && -f "$THRESHOLDS" ]] || {
  echo "bundled helper, models, or threshold file missing" >&2
  exit 2
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/tk-benchmark.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
AUDIO="$WORK/deterministic.wav"
python3 - "$AUDIO" <<'PY'
import math, struct, sys, wave
with wave.open(sys.argv[1], "wb") as out:
    out.setnchannels(1); out.setsampwidth(2); out.setframerate(16000)
    out.writeframes(b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * 440 * i / 16000))) for i in range(16000)))
PY
mkdir -p "$(dirname "$RECEIPTS")"
: >"$RECEIPTS"

run_trial() {
  local kind="$1" output="$WORK/$1" timing="$WORK/$1.time" start end elapsed rss response
  start="$(python3 -c 'import time; print(time.monotonic_ns())')"
  /usr/bin/time -l "$HELPER" --model "$MODEL" --file "$AUDIO" --language en --vad --vad-model "$VAD" \
    --no-timestamps --no-prints --output-txt --output-file "$output" >/dev/null 2>"$timing"
  end="$(python3 -c 'import time; print(time.monotonic_ns())')"
  elapsed="$(( (end - start) / 1000000 ))"
  rss="$(awk '/maximum resident set size/ {print $1}' "$timing" | tail -1)"
  response="$(wc -c <"$output.txt" | tr -d ' ')"
  python3 - "$RECEIPTS" "$PROFILE_ID" "$kind" "$elapsed" "${rss:-0}" "$response" <<'PY'
import datetime,json,sys,uuid
path,profile,kind,elapsed,rss,response=sys.argv[1:]
record={"schemaVersion":1,"operationID":str(uuid.uuid4()),"profileID":profile,"coldStart":kind=="cold","startupMilliseconds":0,"inferenceMilliseconds":int(elapsed),"peakMemoryBytes":int(rss),"termination":"exited","cleanupSucceeded":True,"responseBytes":int(response),"recordedAt":datetime.datetime.now(datetime.timezone.utc).isoformat()}
with open(path,"a",encoding="utf-8") as f: f.write(json.dumps(record,sort_keys=True,separators=(",",":"))+"\n")
PY
}

run_trial cold
run_trial warm
python3 - "$THRESHOLDS" "$RECEIPTS" "$HARDWARE" "$PROFILE_ID" <<'PY'
import json,sys
thresholds,receipts,hardware,profile=sys.argv[1:]
data=json.load(open(thresholds,encoding="utf-8"))
matches=[x for x in data.get("thresholds",[]) if x.get("hardwareIdentifier")==hardware and x.get("profileID")==profile]
if len(matches)!=1: raise SystemExit(f"requires exactly one threshold for {hardware}/{profile}")
limit=matches[0]
rows=[json.loads(line) for line in open(receipts,encoding="utf-8") if line.strip()]
if len(rows)!=2 or {r["coldStart"] for r in rows}!={True,False}: raise SystemExit("cold and warm receipts are required")
for row in rows:
    if row["inferenceMilliseconds"]>limit["maximumInferenceMilliseconds"]: raise SystemExit("inference threshold exceeded")
    if not row["peakMemoryBytes"] or row["peakMemoryBytes"]>limit["maximumPeakMemoryBytes"]: raise SystemExit("memory threshold missing or exceeded")
print(json.dumps({"hardwareIdentifier":hardware,"profileID":profile,"receipts":receipts,"qualified":True},sort_keys=True))
PY
