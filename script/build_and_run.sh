#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

usage() {
  echo "usage: $0 [run|--build|--install|--debug|--logs|--telemetry|--verify|--dmg|--release|--help]"
}

case "$MODE" in
  run|--build|build|--debug|debug|--logs|logs|--telemetry|telemetry|--install|install|--verify|verify|--dmg|dmg|--release|release)
    ;;
  --help|-h|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

APP_NAME="tk"
BUNDLE_ID="com.local.tk"
VERSION="${TK_VERSION:-0.1.0}"
BUILD_NUMBER="${TK_BUILD_NUMBER:-1}"
SPARKLE_FEED_URL="${TK_SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${TK_SPARKLE_PUBLIC_ED_KEY:-}"
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
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Assets/tk.icns"
ENTITLEMENTS="$ROOT_DIR/Assets/tk.entitlements"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
WHISPER_SOURCE="$ROOT_DIR/.build/vendor/whisper.cpp"
WHISPER_BUILD="$WHISPER_SOURCE/build-apple"
WHISPER_BINARY="$WHISPER_BUILD/bin/whisper-cli"
BABYLON_SOURCE="$ROOT_DIR/.build/vendor/babylon"
BABYLON_BUILD="$BABYLON_SOURCE/build-apple"
BABYLON_BIN="$BABYLON_SOURCE/bin-apple"
BABYLON_BINARY="$BABYLON_BIN/babylon"
MODEL_DIR="$HOME/Library/Application Support/tk/models"
WHISPER_PID_FILE="$HOME/Library/Application Support/tk/whisper-server.pid"
BABYLON_PID_FILE="$HOME/Library/Application Support/tk/babylon-server.pid"
MODEL_FILE="$MODEL_DIR/$MODEL_NAME"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/$MODEL_NAME"
VAD_MODEL_FILE="$MODEL_DIR/$VAD_MODEL_NAME"
VAD_MODEL_URL="https://huggingface.co/ggml-org/whisper-vad/resolve/main/$VAD_MODEL_NAME"
KOKORO_MODEL_FILE="$MODEL_DIR/$KOKORO_MODEL_NAME"
KOKORO_MODEL_URL="https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx/model.onnx"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "TK_VERSION must be a dotted number and TK_BUILD_NUMBER must be an integer." >&2
  exit 2
fi

if [[ -n "$SPARKLE_FEED_URL" || -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  if [[ -z "$SPARKLE_FEED_URL" || -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "Set both TK_SPARKLE_FEED_URL and TK_SPARKLE_PUBLIC_ED_KEY, or neither." >&2
    exit 2
  fi
  if [[ "$SPARKLE_FEED_URL" != https://* ]]; then
    echo "TK_SPARKLE_FEED_URL must use HTTPS." >&2
    exit 2
  fi
fi

SIGNING_IDENTITY="${TK_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${TK_NOTARY_PROFILE:-}"
NOTARY_KEYCHAIN="${TK_NOTARY_KEYCHAIN:-}"
NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "$NOTARY_KEYCHAIN" ]]; then
  NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
fi
if [[ "$MODE" == "--release" || "$MODE" == "release" ]]; then
  if [[ -z "$SIGNING_IDENTITY" || -z "$NOTARY_PROFILE" || -z "$SPARKLE_FEED_URL" ]]; then
    echo "Set signing, notarization, and Sparkle update variables before building a release." >&2
    exit 2
  fi
  if ! security find-identity -p codesigning -v | grep -F "$SIGNING_IDENTITY" | grep -Fq "Developer ID Application:"; then
    echo "TK_SIGNING_IDENTITY must name an installed Developer ID Application identity." >&2
    exit 2
  fi
  if ! xcrun notarytool history "${NOTARY_ARGS[@]}" >/dev/null; then
    echo "TK_NOTARY_PROFILE is not a usable notarytool keychain profile." >&2
    exit 2
  fi
fi

stop_recorded_process() {
  local record_file="$1"
  local executable_name="$2"
  local process_identifier=""
  local executable_path=""

  [[ -f "$record_file" ]] || return 0
  process_identifier="$(/usr/bin/plutil -extract processIdentifier raw -o - "$record_file" 2>/dev/null || true)"
  executable_path="$(/usr/bin/plutil -extract executablePath raw -o - "$record_file" 2>/dev/null || true)"
  if [[ ! "$process_identifier" =~ ^[0-9]+$ ]]; then
    read -r process_identifier <"$record_file" || true
  fi

  if [[ "$process_identifier" =~ ^[0-9]+$ ]] && ((process_identifier > 1)); then
    local running_path
    running_path="$(ps -ww -p "$process_identifier" -o comm= 2>/dev/null || true)"
    if [[ -n "$executable_path" && "$running_path" == "$executable_path" ]] ||
       [[ -z "$executable_path" && "$running_path" == */"$executable_name" ]]; then
      kill "$process_identifier" >/dev/null 2>&1 || true
      for _ in {1..20}; do
        kill -0 "$process_identifier" >/dev/null 2>&1 || break
        sleep 0.05
      done
      kill -KILL "$process_identifier" >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$record_file"
}

checksum() {
  shasum -a 256 "$1" | awk '{print $1}'
}

verify_checksum() {
  local file="$1"
  local expected="$2"
  local label="$3"
  [[ "$(checksum "$file")" == "$expected" ]] || {
    echo "$label checksum failed: $file" >&2
    return 1
  }
}

ensure_model() {
  local file="$1"
  local url="$2"
  local expected="$3"
  local label="$4"
  if [[ -f "$file" ]]; then
    verify_checksum "$file" "$expected" "$label"
    return
  fi

  local download="$file.download"
  curl -fL --retry 3 --retry-all-errors --continue-at - "$url" -o "$download"
  verify_checksum "$download" "$expected" "Downloaded $label" || {
    rm -f "$download"
    return 1
  }
  mv "$download" "$file"
}

stop_recorded_process "$WHISPER_PID_FILE" "whisper-server"
stop_recorded_process "$BABYLON_PID_FILE" "babylon"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ ! -x "$WHISPER_BINARY" ]] ||
   [[ "$(git -C "$WHISPER_SOURCE" describe --tags --exact-match HEAD 2>/dev/null || true)" != "$WHISPER_VERSION" ]]; then
  if [[ ! -d "$WHISPER_SOURCE/.git" ]]; then
    if [[ -e "$WHISPER_SOURCE" ]]; then
      echo "Whisper source exists but is not a Git checkout: $WHISPER_SOURCE" >&2
      exit 1
    fi
    git clone --branch "$WHISPER_VERSION" --depth 1 \
      https://github.com/ggml-org/whisper.cpp.git "$WHISPER_SOURCE"
  else
    if ! git -C "$WHISPER_SOURCE" cat-file -e "$WHISPER_VERSION^{commit}" 2>/dev/null; then
      git -C "$WHISPER_SOURCE" fetch --depth 1 origin \
        "refs/tags/$WHISPER_VERSION:refs/tags/$WHISPER_VERSION"
    fi
    git -C "$WHISPER_SOURCE" checkout --detach "$WHISPER_VERSION"
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
  git -C "$BABYLON_SOURCE" submodule deinit --force --all || true
  rm -rf \
    "$BABYLON_SOURCE/.git/modules/submodules/json" \
    "$BABYLON_SOURCE/.git/modules/submodules/onnxruntime" \
    "$BABYLON_SOURCE/submodules/json" \
    "$BABYLON_SOURCE/submodules/onnxruntime"
  git -C "$BABYLON_SOURCE" submodule update --init --recursive --depth 1 --jobs 1
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
ensure_model "$MODEL_FILE" "$MODEL_URL" "$MODEL_SHA256" "Whisper model"
ensure_model "$VAD_MODEL_FILE" "$VAD_MODEL_URL" "$VAD_MODEL_SHA256" "VAD model"
ensure_model "$KOKORO_MODEL_FILE" "$KOKORO_MODEL_URL" "$KOKORO_MODEL_SHA256" "Kokoro model"

verify_checksum \
  "$BABYLON_SOURCE/models/open-phonemizer.onnx" \
  "62d45a3e86e6cb111af7119a26625a2a35f979a19b7e8a7a8125ba9aaf00ad23" \
  "Phonemizer model"
verify_checksum \
  "$BABYLON_SOURCE/data/dictionary.json" \
  "b1c3470c62ffe625e3efcef938d1c22a5be2e1df7ee3489945e81a8eb4e9dd1e" \
  "Babylon dictionary"

BUILD_CONFIGURATION="debug"
if [[ "$MODE" == "--dmg" || "$MODE" == "dmg" || "$MODE" == "--release" || "$MODE" == "release" ]]; then
  BUILD_CONFIGURATION="release"
fi
swift build --package-path "$ROOT_DIR" --configuration "$BUILD_CONFIGURATION" --product "$APP_NAME"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --configuration "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts" -type d -name Sparkle.framework -print -quit)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework was not found in SwiftPM build artifacts." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
cp "$WHISPER_BINARY" "$APP_RESOURCES/whisper-cli"
cp "$WHISPER_SOURCE/LICENSE" "$APP_RESOURCES/Whisper-LICENSE"
cp "$ROOT_DIR/Assets/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
cat >"$APP_RESOURCES/uninstall.json" <<EOF
{"schemaVersion":1,"applicationSupport":["~/Library/Application Support/tk"],"installedApp":"tk.app","userInitiated":true}
EOF
cat >"$APP_RESOURCES/rollback.json" <<EOF
{"schemaVersion":1,"strategy":"install-prior-notarized-dmg","preservesPendingText":true}
EOF
cat >"$APP_RESOURCES/network-policy.json" <<EOF
{"schemaVersion":1,"offlineOperation":true,"runtimeDownloadsRequired":false,"residentListener":false}
EOF
cp "$APP_ICON" "$APP_RESOURCES/tk.icns"
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
cp "$BABYLON_SOURCE/submodules/onnxruntime/rust/LICENSE-APACHE" \
  "$KOKORO_RESOURCES/Kokoro-ONNX-Apache-2.0-LICENSE"
chmod +x "$APP_BINARY"
chmod +x "$APP_RESOURCES/whisper-cli"
chmod +x "$KOKORO_RESOURCES/babylon"
if ! /usr/bin/otool -l "$APP_BINARY" | grep -Fq '@executable_path/../Frameworks'; then
  /usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BINARY"
fi

if [[ "$MODE" == "--dmg" || "$MODE" == "dmg" || "$MODE" == "--release" || "$MODE" == "release" ]]; then
  mkdir -p "$APP_RESOURCES/models"
  cp "$MODEL_FILE" "$VAD_MODEL_FILE" "$KOKORO_MODEL_FILE" "$APP_RESOURCES/models/"
  python3 - "$APP_RESOURCES/qualification.wav" <<'PY'
import struct,sys,wave
with wave.open(sys.argv[1],"wb") as output:
    output.setnchannels(1); output.setsampwidth(2); output.setframerate(16000)
    output.writeframes(struct.pack("<16000h", *([0] * 16000)))
PY
fi

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
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>tk.icns</string>
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

if [[ -n "$SPARKLE_FEED_URL" ]]; then
  /usr/bin/plutil -insert SUFeedURL -string "$SPARKLE_FEED_URL" "$INFO_PLIST"
  /usr/bin/plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
fi

sign_distribution() {
  local identity="$1"
  while IFS= read -r library; do
    /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime "$library"
  done < <(find "$KOKORO_RESOURCES/lib" -type f -name '*.dylib' -print)
  /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime "$KOKORO_RESOURCES/babylon"
  /usr/bin/codesign --force --sign "$identity" --timestamp --options runtime "$APP_RESOURCES/whisper-cli"
  /usr/bin/codesign --force --deep --sign "$identity" --timestamp --options runtime "$APP_FRAMEWORKS/Sparkle.framework"
  /usr/bin/codesign \
    --force \
    --sign "$identity" \
    --timestamp \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"
}

create_dmg() {
  local staging
  staging="$(mktemp -d)"
  /usr/bin/ditto "$APP_BUNDLE" "$staging/$APP_NAME.app"
  ln -s /Applications "$staging/Applications"
  rm -f "$DMG_PATH"
  if ! /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$staging" \
    -ov \
    -format UDZO \
    "$DMG_PATH"; then
    rm -rf "$staging"
    return 1
  fi
  rm -rf "$staging"
}

if [[ "$MODE" == "--release" || "$MODE" == "release" ]]; then
  sign_distribution "$SIGNING_IDENTITY"
else
  DEVELOPMENT_ENTITLEMENTS="$(mktemp)"
  cp "$ENTITLEMENTS" "$DEVELOPMENT_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$DEVELOPMENT_ENTITLEMENTS"
  /usr/bin/codesign --force --deep --sign - --options runtime "$APP_FRAMEWORKS/Sparkle.framework"
  /usr/bin/codesign --force --deep --sign - --options runtime --entitlements "$DEVELOPMENT_ENTITLEMENTS" "$APP_BUNDLE"
  rm -f "$DEVELOPMENT_ENTITLEMENTS"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$MODE" == "--dmg" || "$MODE" == "dmg" || "$MODE" == "--release" || "$MODE" == "release" ]]; then
  create_dmg
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build|build)
    echo "Built $APP_BUNDLE"
    ;;
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
      --model "$MODEL_FILE" \
      --file "$VERIFY_DIR/input.wav" \
      --language en \
      --vad \
      --vad-model "$VAD_MODEL_FILE" \
      --no-timestamps \
      --no-prints \
      --output-txt \
      --output-file "$VERIFY_DIR/transcript" \
      >/dev/null 2>&1
    VERIFY_TRANSCRIPT="$(cat "$VERIFY_DIR/transcript.txt")"
    [[ "$VERIFY_TRANSCRIPT" == *"fellow Americans"* ]]
    /usr/bin/afconvert \
      "$WHISPER_SOURCE/samples/jfk.wav" \
      "$VERIFY_DIR/silence.wav" \
      -f WAVE -d LEI16@16000 -c 1 -m -1
    "$APP_RESOURCES/whisper-cli" \
      --model "$MODEL_FILE" \
      --file "$VERIFY_DIR/silence.wav" \
      --language en \
      --vad \
      --vad-model "$VAD_MODEL_FILE" \
      --no-timestamps \
      --no-prints \
      --output-txt \
      --output-file "$VERIFY_DIR/silence-transcript" \
      >/dev/null 2>&1
    [[ ! -s "$VERIFY_DIR/silence-transcript.txt" ]]
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
  --dmg|dmg)
    echo "Created $DMG_PATH"
    ;;
  --release|release)
    /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
    xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
    /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
    echo "Created signed and notarized $DMG_PATH"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
