# Decide the Reading profile portfolio

Type: grilling
Status: resolved
Blocked by: 02
Parent: [Make local speech profiles understandable and selectable](../map.md)

## Question

Which researched Reading profiles should tk offer, what non-technical names and “Best for” descriptions should each use, which remains the default, and how should profile choice interact with the existing independent Voice choice and verified compatibility limits?

## Answer

Offer two Reading profiles. A third “Balanced” tier would add choice without a verified benefit.

| Reading quality | Best for | Download | Memory | Initial state |
| --- | --- | ---: | --- | --- |
| **Lower memory** | Macs where storage and memory matter more than how quickly reading begins | 92.4 MB (88.1 MiB) | Lower | Optional explicit download |
| **Best quality — Recommended** | Natural everyday reading | 325.5 MB (310.5 MiB) | Moderate | Current bundled default |

“Lower memory” uses the 8-bit artifact. Do not label it “Fast”: on the tested supported stack it used less storage and resident memory but took longer to generate speech than the current FP32 model. “Best quality” is the unquantized FP32 baseline; do not promise a quantified quality difference or universal speed advantage.

Voice remains a separate setting. Switching Reading quality preserves the selected Voice and does not filter the voice list. Both profiles use the same 54 voice files, phonemizer, dictionary, and eight supported voice languages: German, Greek, English (UK and US), French, Italian, Japanese, Brazilian Portuguese, and Chinese.

Installing a profile does not select it. Selection is a deliberate second action and applies to the next Read request without restarting the app. A failure to load the selected profile must be shown explicitly; never silently fall back.

The primary card shows the user-facing name, “Best for” text, exact download size, relative memory label, and download/selected state. Keep artifact names, hashes, and license details behind technical details. Disable Download only when exact available storage is insufficient for the artifact plus the temporary space required for an atomic install. Do not use numeric RAM gates: the available measurements come from one M4 Mac and are directional, not minimum requirements.

Long selections need no profile-specific warning because the existing reader chunks them before inference. Common limitations should state the supported voice languages and avoid promising perfect pronunciation. Release packaging and required notices remain part of the download-lifecycle decision.

Pin both artifacts to Kokoro revision `1939ad2a8e416c0acfeecc08a694d14ef25f2231` and verify before installation:

- Lower memory: `model_quantized.onnx`, SHA-256 `fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478`.
- Best quality: `model.onnx`, SHA-256 `8fbea51ea711f2af382e88c833d9e288c6dc82ce5e98421ea61c058ce21a34cb`.
