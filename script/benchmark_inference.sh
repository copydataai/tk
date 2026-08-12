#!/usr/bin/env bash
set -euo pipefail

if [[ "${TK_RUN_HEAVY_BENCHMARK:-0}" != "1" ]]; then
  echo "SKIP: set TK_RUN_HEAVY_BENCHMARK=1 to benchmark the bundled helper" >&2
  exit 77
fi

APP="${1:-dist/tk.app}"
HELPER="$APP/Contents/Resources/whisper/whisper-cli"
MODEL="$APP/Contents/Resources/whisper/ggml-large-v3-turbo-q5_0.bin"
[[ -x "$HELPER" && -f "$MODEL" ]] || { echo "bundled helper or model missing" >&2; exit 2; }
echo "hardware=$(sysctl -n hw.model)"
echo "memory_bytes=$(sysctl -n hw.memsize)"
echo "helper_sha256=$(shasum -a 256 "$HELPER" | awk '{print $1}')"
echo "model_sha256=$(shasum -a 256 "$MODEL" | awk '{print $1}')"
