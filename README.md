# tk

`tk` is a privacy-first macOS app for voice and text. Dictation runs locally with Whisper large-v3-turbo Q5 and reading uses Kokoro 82M FP32, so speech and text stay on your Mac.

## What it does

- Press a global shortcut, speak, and press it again to insert the transcription or copy it yourself in microphone-only Copy Mode.
- Select text in another app and read it aloud with a second global shortcut.
- Preview Kokoro's multilingual voices by language, then adjust speed and volume.
- Review previous dictations in local, on-device history.
- Choose shortcut presets from the app window.
- Keep running from the menu bar.

## Requirements

- macOS 14 or newer
- Apple silicon with at least 16 GB of memory; 24 GB is recommended
- About 1.1 GB of disk space for the app and cached speech models
- Microphone permission for dictation
- Accessibility permission only for automatic insertion and Read Selection

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

Before a release, complete the real-device checks in [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) and record one result per row in the [compatibility and hardening matrix](docs/COMPATIBILITY.md). The matrix covers insertion receipts and target refusal, Accessibility-denied Copy Mode, sleep during recording and transcription, wake/retry, built-in/USB/Bluetooth disconnect and reconnect behavior, memory and thermal pressure, helper crash and stale cleanup, the per-operation no-listener boundary, retention-zero and Clear All scope, and clean-install offline DMG behavior.

Matrix statuses are only `Pass`, `Fail`, `Blocked`, or `Not run`. Results do not transfer between macOS versions, target classes, devices, phases, or operations. `Not run` is not release evidence. Every failure requires a linked issue and an explicit `SHIP` or `HOLD` disposition. Automated Swift tests support the record but do not qualify physical microphone, sleep/wake, pressure, or installed-DMG rows.

## First use

1. Open `tk`, enable Microphone, and click **Get Started**. Accessibility is optional during onboarding.
2. Without Accessibility, dictate in Copy Mode and choose **Copy** after the transcription is ready. Clipboard contents can be read by other processes on your Mac.
3. To enable automatic insertion or Read Selection, enable Accessibility in macOS System Settings.
4. `tk` automatically uses the last working microphone and falls back to another connected input when needed.
5. Open **Read aloud** to preview a voice, or select text in another app and press the read shortcut after granting Accessibility.

Voice settings are saved automatically. Transcript text, timestamps, trust metadata, optional source operation IDs, and retention disposition are stored with macOS SQLite at `~/Library/Application Support/tk/history.sqlite3`; microphone audio is not retained. New and legacy history rows are treated as `untrustedSpeechRecognition` and `ineligible` for agent use, and JSON history exports preserve those safe labels.

**Clear All** deletes transcript rows with SQLite `secure_delete=ON`, checkpoints and truncates the write-ahead log, and removes explicitly selected application-controlled corrupt archives and the pending dictation artifact. Its deletion receipt lists successes, failures, and exclusions. This is not an SSD secure-erasure claim: filesystem snapshots, backups, controller-managed flash blocks, and free space remain outside the app's control. Setting history retention to zero removes history records but preserves a separately pending recovery result until it is explicitly discarded or included in **Clear All**.

Default shortcuts:

- Dictation: `⌃⌥Space`
- Read selection: `⌃⌥R`

## Current scope

Dictation is processed after recording stops, rather than streamed while speaking. Copy Mode records, transcribes, and persists pending text without Accessibility, focus capture, selected-text access, or synthetic key events. Copying is always user initiated. Automatic insertion and Read Selection remain disabled until Accessibility is granted. In insertion mode, `tk` can fall back to copy/paste events for standard text controls while restoring the clipboard afterward.

## Publish a release

Automatic updates use Sparkle 2.9.5. A source build that does not provide update configuration remains safe for development: Sparkle is embedded, but its updater does not start and **Check for Updates...** is disabled.

Before publishing updates:

1. Run Sparkle's `generate_keys` tool once. It stores the EdDSA private key in the login keychain and prints the public key. Keep the private key available only to the release process; losing it prevents signing future updates for existing installations.
2. Host an appcast XML file and release downloads over HTTPS. Each appcast enclosure must use Sparkle's EdDSA signature and include the monotonically increasing `sparkle:version` matching `TK_BUILD_NUMBER`. `generate_appcast` from the same Sparkle release can sign archives and update the appcast.
3. Set `TK_SPARKLE_PUBLIC_ED_KEY` to the public key and `TK_SPARKLE_FEED_URL` to the absolute HTTPS appcast URL. Both values are written to the bundle as `SUPublicEDKey` and `SUFeedURL`; neither secret key material nor signing credentials are embedded.

The Sparkle command-line tools are included in the SwiftPM artifact under `.build/artifacts/sparkle/Sparkle/bin/` after dependency resolution. See the [Sparkle documentation](https://sparkle-project.org/documentation/) for key rotation, appcast generation, archive formats, and phased releases.

Store notarization credentials once with `xcrun notarytool store-credentials`, then run:

```sh
TK_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
TK_NOTARY_PROFILE="tk-notary" \
TK_SPARKLE_FEED_URL="https://updates.example.com/tk/appcast.xml" \
TK_SPARKLE_PUBLIC_ED_KEY="base64-public-key-from-generate_keys" \
TK_VERSION="0.2.0" \
TK_BUILD_NUMBER="2" \
./script/build_and_run.sh --release
```

The command copies `Sparkle.framework` into the app, signs the framework and bundled executables with the hardened runtime, creates the DMG, submits it to Apple for notarization, staples the ticket, and verifies Gatekeeper acceptance. It fails before building if the Developer ID identity, keychain profile, feed URL, or public update key is missing. Afterward, sign the distributable archive with the Sparkle private key and publish its appcast entry; Apple code signing and notarization do not replace Sparkle's EdDSA signature.

Pushing a `v<version>` tag runs `.github/workflows/release.yml`. Configure these GitHub Actions secrets first: `MACOS_SIGNING_IDENTITY`, `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `RELEASE_KEYCHAIN_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD`, `SPARKLE_PUBLIC_ED_KEY`, and `SPARKLE_PRIVATE_KEY`. The workflow signs and notarizes the DMG, creates its SHA256 file, generates a signed `appcast.xml`, and publishes all three files to the GitHub Release.
