# tk

`tk` is a privacy-first macOS app for voice and text. Dictation runs locally with Whisper large-v3-turbo Q5 and reading uses Kokoro 82M FP32, so speech and text stay on your Mac.

## What it does

- Press a global shortcut, speak, and press it again to insert the transcription wherever the text cursor is active.
- Select text in another app and read it aloud with a second global shortcut.
- Preview Kokoro's multilingual voices by language, then adjust speed and volume.
- Review previous dictations in local, on-device history.
- Choose shortcut presets from the app window.
- Keep running from the menu bar.

## Requirements

- macOS 14 or newer
- Apple silicon with at least 16 GB of memory; 24 GB is recommended
- About 1.1 GB of disk space for the app and cached speech models
- Microphone and Accessibility permissions

`tk` never falls back to cloud recognition. The multilingual model detects the spoken language automatically.

## Install a release

1. Open the downloaded `tk-<version>.dmg`.
2. Drag **tk** to **Applications**.
3. Open **tk** and follow the two permission prompts.

Release builds include the speech models and work offline. No Terminal, package manager, account, or model download is required.

## Build from source

Building requires Xcode command-line tools, CMake, Git, and curl.

From this checkout:

```sh
./script/build_and_run.sh --install
```

This builds the app, downloads and verifies its local speech models, installs it at `~/Applications/tk.app`, and opens it. Run the same command again to update the installation.

To create the same self-contained drag-to-install disk image locally:

```sh
./script/build_and_run.sh --dmg
```

The result is written to `dist/tk-0.1.0.dmg`.

## Run locally

```sh
./script/build_and_run.sh
```

On first use, the script builds pinned Whisper and Babylon ONNX runtimes, downloads and verifies the Whisper and full-precision Kokoro models, creates `dist/tk.app`, and launches it. The first native build also needs several GB of temporary build space; later builds reuse the cached artifacts. The Codex **Run** action calls the same script.

To build without launching:

```sh
./script/build_and_run.sh --build
```

To run the automated checks:

```sh
swift test
bash -n script/build_and_run.sh
```

To build, launch, and confirm that the process started:

```sh
./script/build_and_run.sh --verify
```

## First use

1. Open `tk` and click **Enable…** beside Accessibility and Microphone.
2. Approve both permissions in macOS System Settings.
3. Return to `tk` and click **Get Started**. `tk` automatically uses the last working microphone and falls back to another connected input when needed.
4. Place the cursor in another app, press the shortcut, speak, then press it again to insert.
5. Open **Read aloud** to preview a voice, or select text in another app and press the read shortcut.

Voice settings are saved automatically. Transcript text and timestamps are stored with macOS SQLite at `~/Library/Application Support/tk/history.sqlite3`; microphone audio is not retained.

Default shortcuts:

- Dictation: `⌃⌥Space`
- Read selection: `⌃⌥R`

## Current scope

Dictation is processed after recording stops, rather than streamed while speaking. Reading and insertion work in apps that expose text through macOS Accessibility; `tk` falls back to copy/paste events for other standard text controls while restoring the clipboard afterward.

## Publish a release

Store notarization credentials once with `xcrun notarytool store-credentials`, then run:

```sh
TK_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
TK_NOTARY_PROFILE="tk-notary" \
./script/build_and_run.sh --release
```

The command signs the bundled executables with the hardened runtime, creates the DMG, submits it to Apple for notarization, staples the ticket, and verifies Gatekeeper acceptance. It fails before building if the Developer ID identity or keychain profile is missing.
