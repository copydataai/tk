# tk

`tk` is a privacy-first macOS app for voice and text. Dictation runs locally with Whisper large-v3-turbo Q5 and reading uses Kokoro 82M FP32, so speech and text stay on your Mac.

## What it does

- Press a global shortcut, speak, and press it again to insert the transcription wherever the text cursor is active.
- Select text in another app and read it aloud with a second global shortcut.
- Choose from Kokoro's multilingual voices and adjust speed and volume.
- Choose shortcut presets from the app window.
- Keep running from the menu bar.

## Requirements

- macOS 14 or newer
- Apple silicon with at least 16 GB of memory; 24 GB is recommended
- Xcode command-line tools, CMake, Git, and curl
- About 1.1 GB of disk space for the app and cached speech models
- Microphone and Accessibility permissions

`tk` never falls back to cloud recognition. The multilingual model detects the spoken language automatically.

## Install

From this checkout:

```sh
./script/build_and_run.sh --install
```

This builds the app, downloads and verifies its local speech models, installs it at `~/Applications/tk.app`, and opens it. Run the same command again to update the installation.

## Run locally

```sh
./script/build_and_run.sh
```

On first use, the script builds pinned Whisper and Babylon ONNX runtimes, downloads and verifies the Whisper and full-precision Kokoro models, creates `dist/tk.app`, and launches it. The first native build also needs several GB of temporary build space; later builds reuse the cached artifacts. The Codex **Run** action calls the same script.

To build without launching:

```sh
swift build
```

To build, launch, and confirm that the process started:

```sh
./script/build_and_run.sh --verify
```

## First use

1. Open `tk` and click **Enable…**.
2. Allow `tk` under **System Settings → Privacy & Security → Accessibility**.
3. In **System Settings → Sound → Input**, choose a microphone that shows input activity. The built-in microphone on recent MacBooks is unavailable while the lid is closed.
4. Press the dictation shortcut once and approve Microphone access.
5. Place the cursor in another app, press the shortcut, speak, then press it again to insert.
6. To hear text, select it in another app and press the read shortcut.

Voice settings are in the **Read selected text** section and are saved automatically.

Default shortcuts:

- Dictation: `⌃⌥Space`
- Read selection: `⌃⌥R`

## Current scope

Dictation is processed after recording stops, rather than streamed while speaking. Reading and insertion work in apps that expose text through macOS Accessibility; `tk` falls back to copy/paste events for other standard text controls while restoring the clipboard afterward.
