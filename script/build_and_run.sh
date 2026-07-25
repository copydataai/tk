#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="tk"
BUNDLE_ID="com.local.tk"
MIN_SYSTEM_VERSION="14.0"
WHISPER_VERSION="v1.9.1"
MODEL_NAME="ggml-large-v3-turbo-q5_0.bin"
MODEL_SHA256="394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
VAD_MODEL_NAME="ggml-silero-v6.2.0.bin"
VAD_MODEL_SHA256="2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987"
BABYLON_COMMIT="208e3d3d0d8305bb7c9ffa7d16a0c889cd0d2cae"
KOKORO_MODEL_NAME="kokoro-v1.0-fp32.onnx"
KOKORO_MODEL_SHA256="8fbea51ea711f2af382e88c833d9e288c6dc82ce5e98421ea61c058ce21a34cb"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
WHISPER_SOURCE="$ROOT_DIR/.build/vendor/whisper.cpp"
WHISPER_BUILD="$WHISPER_SOURCE/build-apple"
WHISPER_BINARY="$WHISPER_BUILD/bin/whisper-cli"
BABYLON_SOURCE="$ROOT_DIR/.build/vendor/babylon"
BABYLON_BUILD="$BABYLON_SOURCE/build-apple"
BABYLON_BIN="$BABYLON_SOURCE/bin-apple"
BABYLON_BINARY="$BABYLON_BIN/babylon"
MODEL_DIR="$HOME/Library/Application Support/tk/models"
MODEL_FILE="$MODEL_DIR/$MODEL_NAME"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_NAME"
VAD_MODEL_FILE="$MODEL_DIR/$VAD_MODEL_NAME"
VAD_MODEL_URL="https://huggingface.co/ggml-org/whisper-vad/resolve/main/$VAD_MODEL_NAME"
KOKORO_MODEL_FILE="$MODEL_DIR/$KOKORO_MODEL_NAME"
KOKORO_MODEL_URL="https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx/model.onnx"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ ! -x "$WHISPER_BINARY" ]]; then
  if [[ ! -d "$WHISPER_SOURCE/.git" ]]; then
    git clone --branch "$WHISPER_VERSION" --depth 1 \
      https://github.com/ggml-org/whisper.cpp.git "$WHISPER_SOURCE"
  fi
  CC=/usr/bin/clang CXX=/usr/bin/clang++ cmake \
    -S "$WHISPER_SOURCE" \
    -B "$WHISPER_BUILD" \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build "$WHISPER_BUILD" --target whisper-cli -j "$(sysctl -n hw.logicalcpu)"
fi

if [[ ! -x "$BABYLON_BINARY" ]] ||
   [[ "$(git -C "$BABYLON_SOURCE" rev-parse HEAD 2>/dev/null || true)" != "$BABYLON_COMMIT" ]]; then
  if [[ ! -d "$BABYLON_SOURCE/.git" ]]; then
    git clone --no-checkout \
      https://github.com/Mobile-Artificial-Intelligence/babylon.git "$BABYLON_SOURCE"
  fi
  if ! git -C "$BABYLON_SOURCE" cat-file -e "$BABYLON_COMMIT^{commit}" 2>/dev/null; then
    git -C "$BABYLON_SOURCE" fetch --depth 1 origin "$BABYLON_COMMIT"
  fi
  git -C "$BABYLON_SOURCE" checkout --detach "$BABYLON_COMMIT"
  git -C "$BABYLON_SOURCE" submodule update --init --recursive
  CC=/usr/bin/clang CXX=/usr/bin/clang++ cmake \
    -S "$BABYLON_SOURCE" \
    -B "$BABYLON_BUILD" \
    -DBUILD_CLI=ON \
    -DBABYLON_BIN_DIR="$BABYLON_BIN" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=Release
  CC=/usr/bin/clang CXX=/usr/bin/clang++ cmake \
    --build "$BABYLON_BUILD" \
    --target babylon_cli \
    -j "$(sysctl -n hw.logicalcpu)"
fi

mkdir -p "$MODEL_DIR"
if [[ -f "$MODEL_FILE" ]]; then
  [[ "$(shasum -a 256 "$MODEL_FILE" | awk '{print $1}')" == "$MODEL_SHA256" ]] || {
    echo "Model checksum failed: $MODEL_FILE" >&2
    exit 1
  }
else
  MODEL_DOWNLOAD="$MODEL_FILE.download"
  curl -fL "$MODEL_URL" -o "$MODEL_DOWNLOAD"
  [[ "$(shasum -a 256 "$MODEL_DOWNLOAD" | awk '{print $1}')" == "$MODEL_SHA256" ]] || {
    echo "Downloaded model checksum failed" >&2
    exit 1
  }
  mv "$MODEL_DOWNLOAD" "$MODEL_FILE"
fi

if [[ -f "$VAD_MODEL_FILE" ]]; then
  [[ "$(shasum -a 256 "$VAD_MODEL_FILE" | awk '{print $1}')" == "$VAD_MODEL_SHA256" ]] || {
    echo "Model checksum failed: $VAD_MODEL_FILE" >&2
    exit 1
  }
else
  VAD_MODEL_DOWNLOAD="$VAD_MODEL_FILE.download"
  curl -fL "$VAD_MODEL_URL" -o "$VAD_MODEL_DOWNLOAD"
  [[ "$(shasum -a 256 "$VAD_MODEL_DOWNLOAD" | awk '{print $1}')" == "$VAD_MODEL_SHA256" ]] || {
    echo "Downloaded VAD model checksum failed" >&2
    exit 1
  }
  mv "$VAD_MODEL_DOWNLOAD" "$VAD_MODEL_FILE"
fi

if [[ -f "$KOKORO_MODEL_FILE" ]]; then
  [[ "$(shasum -a 256 "$KOKORO_MODEL_FILE" | awk '{print $1}')" == "$KOKORO_MODEL_SHA256" ]] || {
    echo "Model checksum failed: $KOKORO_MODEL_FILE" >&2
    exit 1
  }
else
  KOKORO_MODEL_DOWNLOAD="$KOKORO_MODEL_FILE.download"
  curl -fL "$KOKORO_MODEL_URL" -o "$KOKORO_MODEL_DOWNLOAD"
  [[ "$(shasum -a 256 "$KOKORO_MODEL_DOWNLOAD" | awk '{print $1}')" == "$KOKORO_MODEL_SHA256" ]] || {
    echo "Downloaded Kokoro model checksum failed" >&2
    exit 1
  }
  mv "$KOKORO_MODEL_DOWNLOAD" "$KOKORO_MODEL_FILE"
fi

[[ "$(shasum -a 256 "$BABYLON_SOURCE/models/open-phonemizer.onnx" | awk '{print $1}')" == \
  "62d45a3e86e6cb111af7119a26625a2a35f979a19b7e8a7a8125ba9aaf00ad23" ]]
[[ "$(shasum -a 256 "$BABYLON_SOURCE/data/dictionary.json" | awk '{print $1}')" == \
  "b1c3470c62ffe625e3efcef938d1c22a5be2e1df7ee3489945e81a8eb4e9dd1e" ]]

swift build --package-path "$ROOT_DIR" --product "$APP_NAME"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$WHISPER_BINARY" "$APP_RESOURCES/whisper-cli"
KOKORO_RESOURCES="$APP_RESOURCES/kokoro"
mkdir -p \
  "$KOKORO_RESOURCES/lib" \
  "$KOKORO_RESOURCES/models" \
  "$KOKORO_RESOURCES/data" \
  "$KOKORO_RESOURCES/voices"
cp "$BABYLON_BINARY" "$KOKORO_RESOURCES/babylon"
cp "$BABYLON_BIN/lib/"*.dylib "$KOKORO_RESOURCES/lib/"
cp "$BABYLON_SOURCE/models/open-phonemizer.onnx" "$KOKORO_RESOURCES/models/"
cp "$BABYLON_SOURCE/data/dictionary.json" "$KOKORO_RESOURCES/data/"
cp "$BABYLON_SOURCE/voices/kokoro/"*.bin "$KOKORO_RESOURCES/voices/"
cp "$BABYLON_SOURCE/LICENSE" "$KOKORO_RESOURCES/Babylon-LICENSE"
chmod +x "$APP_BINARY"
chmod +x "$APP_RESOURCES/whisper-cli"
chmod +x "$KOKORO_RESOURCES/babylon"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>tk uses the microphone to turn your speech into text.</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --install|install)
    mkdir -p "$(dirname "$INSTALLED_APP")"
    rm -rf "$INSTALLED_APP"
    /usr/bin/ditto "$APP_BUNDLE" "$INSTALLED_APP"
    /usr/bin/open -n "$INSTALLED_APP"
    echo "Installed $APP_NAME to $INSTALLED_APP"
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    VERIFY_DIR="$(mktemp -d)"
    trap 'rm -rf "$VERIFY_DIR"' EXIT
    /usr/bin/afconvert \
      "$WHISPER_SOURCE/samples/jfk.wav" \
      "$VERIFY_DIR/input.caf" \
      -f caff -d LEF32@48000 -c 1
    /usr/bin/afconvert \
      "$VERIFY_DIR/input.caf" \
      "$VERIFY_DIR/input.wav" \
      -f WAVE -d LEI16@16000 -c 1
    "$APP_RESOURCES/whisper-cli" \
      -m "$MODEL_FILE" \
      -f "$VERIFY_DIR/input.wav" \
      --vad -vm "$VAD_MODEL_FILE" \
      -l en -otxt -of "$VERIFY_DIR/transcript" -np -nt \
      >/dev/null 2>&1
    grep -q "fellow Americans" "$VERIFY_DIR/transcript.txt"
    /usr/bin/afconvert \
      "$WHISPER_SOURCE/samples/jfk.wav" \
      "$VERIFY_DIR/silence.wav" \
      -f WAVE -d LEI16@16000 -c 1 -m -1
    "$APP_RESOURCES/whisper-cli" \
      -m "$MODEL_FILE" \
      -f "$VERIFY_DIR/silence.wav" \
      --vad -vm "$VAD_MODEL_FILE" \
      -l en -otxt -of "$VERIFY_DIR/silence" -np -nt \
      >/dev/null 2>&1
    [[ ! -s "$VERIFY_DIR/silence.txt" ]]
    "$KOKORO_RESOURCES/babylon" \
      --phonemizer-model "$KOKORO_RESOURCES/models/open-phonemizer.onnx" \
      --dictionary "$KOKORO_RESOURCES/data/dictionary.json" \
      --kokoro-model "$KOKORO_MODEL_FILE" \
      --kokoro-voices "$KOKORO_RESOURCES/voices" \
      tts --voice en-US-heart \
      "TK reads selected text privately and locally." \
      -o "$VERIFY_DIR/speech.wav" \
      >/dev/null 2>&1
    [[ -s "$VERIFY_DIR/speech.wav" ]]
    /usr/bin/afinfo "$VERIFY_DIR/speech.wav" | grep -q "24000 Hz"
    ;;
  *)
    echo "usage: $0 [run|--install|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
