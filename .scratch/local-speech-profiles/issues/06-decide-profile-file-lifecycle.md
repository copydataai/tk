# Decide the profile download and file lifecycle

Type: grilling
Status: resolved
Blocked by: 01, 02
Parent: [Make local speech profiles understandable and selectable](../map.md)

## Question

What exact lifecycle should govern explicit downloads, checksum verification, cancellation, interrupted or partial files, free-space checks, removal, bundled defaults, app upgrades, license notices and attribution, release packaging, and model load failures while keeping all inference local and avoiding silent fallback?

## Answer

Use the existing model lifecycle as the production baseline: release-pinned HTTPS URLs, an adjacent partial file, SHA-256 verification, and an atomic rename into `~/Library/Application Support/tk/models`. Extend it into the app with the following contract.

### Catalog and packaging

- Compile a fixed profile manifest into each app release. Each entry contains the profile ID and kind, display copy, immutable source revision and HTTPS URL, exact byte count, SHA-256, runtime compatibility, filename, and license/attribution references. Do not fetch a live catalog.
- Keep the current Balanced Dictation profile, Best quality Reading profile, shared VAD, phonemizer, dictionary, and voices bundled and code-signed in the app. They work on first launch without a download and cannot be removed.
- Do not bundle optional profiles. Download them only after the person presses Download and make clear that this one action uses the internet; inference remains local afterward.
- Continue using the existing flat Application Support model directory and unique pinned filenames. Do not copy bundled defaults into it.
- Package notices for every bundled or downloadable dependency with the app, and expose them under Technical details. Include whisper.cpp and OpenAI Whisper MIT notices, Babylon MIT, Kokoro/ONNX Apache-2.0, source revision, and artifact attribution. For Dictation weights with conflicting MIT and Apache metadata, retain both notices and the immutable source metadata rather than asserting a narrower single license.

### Download and verification

- Allow one model download at a time. Other Download actions remain visible but disabled with “Another download is in progress.”
- Before starting, query available capacity on the destination volume. The required capacity is the artifact's exact byte count minus any valid partial bytes already present; the partial file becomes the final file by same-volume atomic rename, so do not claim or require double the artifact size. If capacity cannot be read, allow the attempt and report an actual filesystem failure.
- Stream into `<final filename>.partial` in the same directory. A partial is never shown as Downloaded and is never selectable.
- Show bytes downloaded, total bytes, progress, and Cancel. Cancel the network task, delete the partial, and return to Download.
- Preserve a partial after a connection interruption or app quit so Retry can resume. Resume only for the same manifest entry and only when the server accepts a byte range with a matching `Content-Range`; otherwise delete it and restart. Delete partials that are larger than expected, belong to an unknown or changed manifest entry, or fail these checks.
- When the expected byte count arrives, compute SHA-256 before installation. On mismatch, delete the partial, leave the prior selection unchanged, and show “The download could not be verified” with Try again. Never load an unverified file.
- Atomically rename a verified partial to its final filename. Only then mark the profile Downloaded. Downloading never selects it; the person must choose it separately.
- Bundled resources rely on the app's code signature. Downloaded files are fully verified at installation and reverified when discovered after an app upgrade or when their size or modification date changes.

### Removal and upgrades

- Remove only the exact optional artifact selected from the manifest; shared files and bundled defaults are never removal targets.
- A downloaded profile that is not selected can be removed after confirmation. While its runtime is serving a request, disable Remove until the request finishes.
- Removing a selected optional profile requires an explicit “Switch to [bundled default] and remove” confirmation. This deliberate action changes the selection; automatic fallback does not.
- App upgrades replace bundled defaults through the signed app bundle. They never automatically download, overwrite, or delete optional complete artifacts.
- Reuse an optional artifact after upgrade only when its identity, expected size, hash, and runtime compatibility still match the new manifest. Otherwise mark it unavailable, do not load it, and offer Remove or the replacement Download. Saved-choice behavior is finalized separately.

### Failures

- A download, verification, storage, removal, or model-load failure is attached to the affected profile in Settings and includes a plain-language cause plus a relevant action: Retry, Free storage, Remove, or Choose another profile.
- A failed optional download or repair leaves the existing selected profile unchanged. A failed load leaves that profile selected but does not run another profile. State that the request did not run and offer Retry, Repair download, or an explicit profile choice.
- Never send text, audio, model data, or inference to a remote service. Network activity is limited to a person-initiated model download from the pinned source.
