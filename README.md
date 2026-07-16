# tk

`tk` is a lightweight, privacy-first macOS app for voice and text. It uses Apple's on-device speech recognition, so dictation stays on your Mac.

## What it does

- Press a global shortcut, speak, and press it again to insert the transcription wherever the text cursor is active.
- Select text in another app and read it aloud with a second global shortcut.
- Choose shortcut presets from the app window.
- Keep running from the menu bar.

## Requirements

- macOS 14 or newer
- A language supported by macOS on-device speech recognition
- Microphone, Speech Recognition, and Accessibility permissions

`tk` never falls back to cloud recognition. If macOS does not provide an on-device recognizer for the current language, the app reports that instead.

## Run locally

```sh
./script/build_and_run.sh
```

The script builds the Swift package, creates `dist/tk.app`, and launches it. The Codex **Run** action calls the same script.

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
3. Press the dictation shortcut once and approve Microphone and Speech Recognition access.
4. Place the cursor in another app, press the shortcut, speak, then press it again to insert.
5. To hear text, select it in another app and press the read shortcut.

Default shortcuts:

- Dictation: `⌃⌥Space`
- Read selection: `⌃⌥R`

## Current scope

This first version uses the speech model already supplied by macOS rather than bundling a separate model runtime. Reading and insertion work in apps that expose text through macOS Accessibility; `tk` falls back to copy/paste events for other standard text controls while restoring the clipboard afterward.
