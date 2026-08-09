# Speech profile implementation and acceptance contract

Status: approved for implementation planning

This is the release-ready contract for local Speech profiles. It consolidates the resolved Wayfinder decisions; where earlier tickets differ, this document governs.

## Product contract

- A **Speech profile** is an independently selected Dictation or Reading quality choice. Technical model names are secondary.
- Existing and new installations initially select `dictation.balanced` and `reading.best-quality`, preserving today's bundled Whisper large-v3-turbo Q5 and Kokoro FP32 behavior.
- Downloading never selects a profile. A selection is a separate explicit action and applies to the next request without restarting tk.
- Dictation language and Reading Voice remain independent choices. Profile operations never rewrite them.
- An unavailable choice remains selected. The affected request is blocked; tk never substitutes another profile, language, Voice, or cloud service.
- Defaults, shared VAD, phonemizer, dictionary, and Voices remain bundled, signed, usable offline on first launch, and non-removable. Optional profiles are downloaded only on explicit request.

## Fixed release manifest

The app ships a signed, compile-time manifest and never fetches a live catalog. Every entry includes the facts below plus its user-facing copy, kind, availability state, license references, supported OS/architecture, and runtime identity. URLs must use the immutable revisions shown.

All five entries support the release's existing `arm64` macOS 14-or-newer target. Dictation entries require bundled `whisper.cpp` v1.9.1 with Metal; Reading entries require bundled Babylon commit `208e3d3d0d8305bb7c9ffa7d16a0c889cd0d2cae`, its current CPU ONNX Runtime, phonemizer, dictionary, and Voice files. Low/Moderate/High memory labels are guidance, not compatibility gates.

| Stable ID | UI name | Local filename | Immutable source URL | Bytes | SHA-256 | Delivery | Runtime / notices |
| --- | --- | --- | --- | ---: | --- | --- | --- |
| `dictation.fast` | Fast | `ggml-small-q5_1.bin` | `https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small-q5_1.bin` | 190,085,487 | `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb` | Optional | Whisper multilingual GGML Q5; OpenAI Whisper and whisper.cpp MIT notices and source attribution |
| `dictation.balanced` | Balanced | `ggml-large-v3-turbo-q5_0.bin` | `https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin` | 574,041,195 | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` | Bundled, recommended default | Whisper multilingual GGML Q5; same notices |
| `dictation.best-quality` | Best quality | `ggml-large-v3-q5_0.bin` | `https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-q5_0.bin` | 1,081,140,203 | `d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1` | Optional | Whisper multilingual GGML Q5; retain both MIT and Apache metadata notices plus immutable provenance until the upstream mismatch is clarified |
| `reading.lower-memory` | Lower memory | `kokoro-v1.0-quantized.onnx` | `https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx/model_quantized.onnx` | 92,361,116 | `fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478` | Optional | Kokoro ONNX 8-bit; Kokoro/ONNX Apache-2.0 and Babylon MIT notices and source attribution |
| `reading.best-quality` | Best quality | `kokoro-v1.0-fp32.onnx` | `https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx/model.onnx` | 325,532,232 | `8fbea51ea711f2af382e88c833d9e288c6dc82ce5e98421ea61c058ce21a34cb` | Bundled, recommended default | Kokoro ONNX FP32; same notices |

Formerly released stable IDs remain as manifest tombstones containing kind, last display name, unavailability reason, and replacement action. Artifact filenames, versions, display labels, and URLs are not identities. Add an explicit alias only when two IDs are known to mean the same choice.

## Exact user-facing presentation

Settings uses the existing macOS Settings window with this sidebar order:

1. General
2. Speech profiles
3. Shortcuts
4. System access

The Speech profiles destination begins with: **“Everything runs privately on this Mac.”** It presents **Dictation quality** first and **Reading quality** second as vertical native radio-style choices. Every row shows its name, the exact friendly download size, relative memory guidance, “Best for” copy, and lifecycle badges/actions. Bundled defaults show **Selected · Recommended** initially. Technical details contains filenames, source revisions, checksums, runtime versions, licenses, and attribution.

### Dictation quality

| Name | Best for | Size shown | Memory | Additional copy |
| --- | --- | ---: | --- | --- |
| **Fast** | “Quick notes when speed and lower resource use matter more than catching every word.” | 181.3 MiB | Low | Optional download |
| **Balanced — Recommended** | “Everyday dictation with a strong balance of speed and accuracy.” | 547.4 MiB | Moderate | Bundled default |
| **Best quality** | “Dictation where the best accuracy offered by tk matters more than waiting and resource use.” | 1.007 GiB | High | Optional download; show a high-memory caution, not a RAM gate |

The Dictation limits disclosure says: **“Dictation may miss, repeat, or invent words. Results vary with language, accent, background noise, and microphone quality.”** All profiles retain Auto and the existing explicit languages, Silero VAD, and post-recording behavior. “Best quality” means best in tk's offered set, not guaranteed or absolute accuracy.

### Reading quality

| Name | Best for | Size shown | Memory | Additional copy |
| --- | --- | ---: | --- | --- |
| **Lower memory** | “Macs where storage and memory matter more than how quickly reading begins.” | 88.1 MiB | Lower | Optional download; may begin reading more slowly |
| **Best quality — Recommended** | “Natural everyday reading.” | 310.5 MiB | Moderate | Bundled default |

The Reading limits disclosure says: **“Voices support German, Greek, English (UK and US), French, Italian, Japanese, Brazilian Portuguese, and Chinese. Pronunciation can vary.”** Voice, speed, and volume stay in Read Aloud. Both profiles use the same 54 Voices. Long selections retain the existing chunked-reading behavior and need no profile warning.

### State and failure copy

- Downloading: **“Downloading [profile]…”**, downloaded bytes, total bytes, progress, and **Cancel**.
- Concurrent attempt: disable other Download actions with **“Another download is in progress.”**
- Verification failure: **“The download could not be verified.”** Action: **Try again**.
- Network interruption: explain the interruption and offer **Retry**; a valid partial may resume.
- Insufficient capacity: **“Not enough free storage. [Profile] needs [remaining exact friendly size] available.”** Action: **Free storage** where actionable.
- Load/inference failure: state that the request did not run and the selected profile did not change. Offer **Retry**, **Repair download**, or **Choose another profile**, as applicable.
- Missing/corrupt/mismatched artifact: show **Selected · Unavailable** with **Download**, **Repair download**, or **Remove** as applicable.
- Verified OS, architecture, or runtime incompatibility: show **Selected · Unavailable**, explain the incompatibility, disable Download/select for a new choice, and offer an explicit compatible choice.
- Retired/newer-version ID: show its tombstone or a generic saved-by-newer-version row and offer an explicit available choice.
- Removing a selected optional profile: confirmation label is **“Switch to [bundled default] and remove.”**

Errors are attached inline to the affected profile, conveyed in text and not color alone, and announce as status changes without moving selection.

## Lifecycle state machine

```text
bundled ───────────────────────────────────────────────→ available
notDownloaded ── Download ──→ downloading ── complete ─→ verifying
downloading ── Cancel ──────→ notDownloaded (delete partial)
downloading ── interruption → interrupted (preserve valid partial)
interrupted ── Retry/range accepted ───────────────────→ downloading
interrupted ── invalid range/manifest ─→ notDownloaded → downloading fresh
verifying ── hash + size match ─→ downloaded (atomic same-volume rename)
verifying ── mismatch ─────────→ failed (delete partial; Try again)
downloaded ── select ──────────→ selectedAvailable
any selected state ── artifact/compatibility/load failure → selectedUnavailable
selectedUnavailable ── repair/reverify succeeds ─────────→ selectedAvailable
downloaded, not selected ── confirmed Remove ────────────→ notDownloaded
selected optional ── “Switch to default and remove” ─────→ notDownloaded
```

There is at most one download at a time. Downloads stream to `<filename>.partial` beside the final file in `~/Library/Application Support/tk/models`. The required free capacity is exact artifact bytes minus valid partial bytes; no second full-size temporary copy is required because verification precedes an atomic rename on the same volume. If capacity cannot be read, allow the attempt and report an actual filesystem failure.

A partial is neither Downloaded nor selectable. Resume only for the same manifest entry when the server accepts the requested range with matching `Content-Range`; otherwise delete and restart. Delete oversized, unknown, changed, or unverifiable partials. Verify exact byte count and SHA-256 before rename and never load unverified data.

Downloaded artifacts are reverified when first discovered after an app upgrade or when size or modification date changes. An upgrade reuses an optional artifact only if identity, size, hash, and runtime compatibility still match. It never downloads, overwrites, or deletes optional artifacts automatically. Bundled artifacts rely on the app signature and are replaced with the app.

Removal targets only the manifest's exact optional artifact. Disable it while that artifact serves a request. Shared resources and bundled defaults are never removal targets.

## Persistence and request compatibility

- Persist profile IDs independently under new Dictation and Reading keys; the implementation may choose the key names but they must be stable and documented.
- Missing keys migrate to `dictation.balanced` and `reading.best-quality`. Missing language remains Auto; missing Voice becomes `en-US-heart`.
- Replace only an empty, non-string, or syntactically invalid saved value with its default. Preserve well-formed unknown IDs.
- Reconcile at launch, after download/removal, and immediately before each request. Reconciliation computes availability and never mutates a valid saved choice.
- Snapshot profile plus Dictation language or Reading Voice at request start. A Settings change affects only the next request.
- Dictation preflights before recording and again before transcription. Reading preflights before obtaining selected text or generating Preview.
- Key each resident local server by artifact identity. Reuse only that identity; stop the idle process and launch the newly selected identity for the next request.
- A load or inference failure fails that request, preserves all choices, and never retries through another profile.
- Preserve `transcriptionLanguageCode` across profile changes. A future incompatible combination remains selected and blocks until the person changes language or profile.
- Preserve `kokoroVoiceIdentifier` across profile changes. Missing/retired/incompatible non-empty Voices block Read and Preview; remove today's silent startup substitution with `en-US-heart`. The Language picker remains a view over Voice locale, and a user-initiated locale change may explicitly choose that locale's first Voice.

## Accessibility and privacy guarantees

- Production uses native SwiftUI Settings navigation, radio choices, buttons, progress, disclosures, alerts, and confirmation dialogs with logical keyboard/focus order, VoiceOver names/values/hints, sufficient contrast, and reduced-motion behavior.
- Selected, Recommended, Downloaded, Unavailable, progress, and errors are available to assistive technology and never communicated by color alone. Dynamic errors and completion are announced without stealing focus.
- Download/Remove/Cancel targets remain operable at standard macOS control sizes; disabled controls expose the reason in adjacent text.
- Dictation audio, selected text, generated audio, model inputs, model data, and inference never leave the Mac. Temporary microphone and generated-audio files keep today's deletion behavior.
- The only profile network activity is a person-initiated HTTPS download from the manifest's pinned source. The UI distinguishes that download from subsequent offline inference. No telemetry, catalog request, cloud fallback, or silent model update is introduced.

## Release and attribution requirements

- Ship notices and immutable provenance for whisper.cpp v1.9.1, OpenAI Whisper weights, Babylon commit `208e3d3d…`, Kokoro/ONNX revision `1939ad2a…`, shared phonemizer/dictionary/Voices, and every bundled or downloadable artifact.
- Include MIT notices for whisper.cpp/OpenAI Whisper and Babylon, Apache-2.0 for Kokoro/ONNX, and both upstream license metadata records for Dictation weights while their mismatch remains unresolved. Do not assert a narrower single license.
- Expose the notices, source revision, artifact attribution, filename, byte count, and checksum under Technical details and include required notice files in release packaging.
- Release notes say defaults and offline behavior are unchanged, optional profiles require an explicit internet download, downloads do not select profiles, and profile choice applies to the next request.

## Acceptance criteria

Implementation is accepted only when deterministic tests or release verification demonstrate:

1. The signed fixed manifest contains exactly the five active IDs and facts above, rejects duplicate IDs/filenames, and retains required tombstones.
2. First migration preserves today's profile, language, Voice, Dictation, Read Aloud, and offline behavior.
3. Each optional download uses its pinned HTTPS URL, exact size, hash, same-directory partial, safe resume rules, verification, and atomic rename; corrupt data is never available or loaded.
4. Download, cancel, resume, interruption, hash mismatch, insufficient storage, one-download-at-a-time, removal, upgrade reuse/mismatch, and runtime load-failure paths produce the contracted state, copy, and actions without changing unrelated choices.
5. Installing or repairing does not select; explicit selection affects the next request without restart and never changes an in-flight request.
6. Missing, corrupt, incompatible, retired, or newer-version selections remain selected/unavailable and block the request without fallback.
7. Dictation preflight happens before recording and before transcription; Reading/Preview preflight happens before selected-text capture or generation.
8. Resident processes never serve a request with an artifact identity different from the request snapshot.
9. Settings matches the hierarchy, profile order, exact copy/sizes/limits, independent Voice behavior, Technical details, and inline lifecycle states above.
10. Keyboard-only and VoiceOver checks can choose profiles, disclose details, operate lifecycle actions, hear progress/errors, and identify selected/unavailable state; contrast and reduced-motion behavior follow system settings.
11. A network audit shows no traffic during Dictation, Read Aloud, Preview, launch reconciliation, or profile selection; only an explicit optional-profile download accesses its pinned host.
12. Release packaging contains bundled defaults, shared speech resources, runtimes, notices, manifest provenance, and no optional profile artifacts.

## Approved assumptions

- The first implementation targets the app's current macOS 14+, Apple-silicon release; no Intel profile support is implied.
- `kokoro-v1.0-quantized.onnx` is the unique local filename for upstream `model_quantized.onnx`; the upstream path remains recorded in the manifest.
- Friendly UI sizes use the binary values shown above while byte counts remain authoritative for validation and storage checks.
- The later lifecycle decision supersedes earlier “artifact plus temporary space” wording: a valid same-volume partial needs only the remaining artifact bytes.
- The existing README's global 16 GB requirement is release guidance, not a per-profile compatibility gate. Profile selection/download is not disabled by total RAM.
- The fixed manifest may update an artifact behind the same stable quality ID in a later app release; that release must provide new immutable provenance and treat older optional bytes as mismatched unless still explicitly listed.
- Existing Settings categories are regrouped into the approved native sidebar; this is navigation inside the current Settings scene, not a new window.

## Explicit unknowns

- Defensible minimum RAM and peak memory across the oldest supported Apple-silicon generations are unknown; do not add numeric gates until measured.
- Perceptual Reading quality across all Voices/languages and quantified Whisper Q5 accuracy differences are unknown; do not promise scores or universal superiority.
- The Whisper weight MIT/Apache metadata mismatch is unresolved; carrying both notices and provenance is the approved release treatment unless release counsel requires a separate hold.
- Behavior of future profiles with different Dictation languages or Voice sets is unspecified beyond the no-substitution compatibility rule.

## Out of scope

- Cloud inference or fallback, accounts, telemetry, or remote processing.
- Custom model import, arbitrary URLs, a live catalog, automatic model updates, or background downloads.
- Live/streaming Dictation, on-device benchmarking, automatic profile recommendations, or invented RAM thresholds.
- New Voices, languages, speech-rate behavior, transcript storage behavior, microphone selection, shortcuts, or redesign of the main Dictation/Read Aloud surfaces.
- Product implementation in this Wayfinder effort; this artifact is the planning handoff.
