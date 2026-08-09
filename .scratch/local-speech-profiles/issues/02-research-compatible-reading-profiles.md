# Research compatible Reading profiles

Type: research
Status: resolved
Blocked by:
Parent: [Make local speech profiles understandable and selectable](../map.md)

## Question

Which Kokoro model precision or quantization artifacts are demonstrably compatible with the pinned Babylon runtime, phonemizer, dictionary, and bundled voice embeddings, and what verified facts support a small Fast/Balanced/Best candidate set: download size, voice/language compatibility, quality tradeoff, realistic memory requirement, license, checksum source, and distribution suitability?

## Answer

Recommend **two Reading profiles, not three**:

| User-facing profile | Artifact at pinned Kokoro revision | Exact download | SHA-256 | Measured idle RSS | Measured generation |
| --- | --- | ---: | --- | ---: | ---: |
| **Uses less memory** | `model_quantized.onnx` (8-bit) | 92,361,116 B (92.4 MB / 88.1 MiB) | `fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478` | 344,320 KiB | 1.93 s mean |
| **Best quality** (current/default) | `model.onnx` (FP32) | 325,532,232 B (325.5 MB / 310.5 MiB) | `8fbea51ea711f2af382e88c833d9e288c6dc82ce5e98421ea61c058ce21a34cb` | 567,920 KiB | 1.11 s mean |

Do not call the 8-bit artifact “Fast.” On the actual supported stack (Apple M4, macOS 15.7.7, pinned Babylon `208e3d3…` and its CPU ONNX Runtime), three warm HTTP generations of the same sentence averaged 1.93 s for 8-bit versus 1.11 s for FP32. It saves about 68% download/storage and 39% measured resident memory, but was about 74% slower in this bounded test.

Do not add a “Balanced” FP16 profile. Although `model_fp16.onnx` is 163,234,740 B with SHA-256 `ba4527a874b42b21e35f468c10d326fdff3c7fc8cac1f85e9eb6c0dfc35c334a`, the pinned runtime measured 984,944 KiB idle RSS and 1.13 s mean generation: similar speed to FP32, more memory, and no published perceptual score proving a useful quality tier. `model_q8f16.onnx` (86,033,585 B; SHA-256 `04c658aec1b6008857c2ad10f8c589d4180d0ec427e7e6118ceb487e215c3cd0`) also loaded, but measured 370,112 KiB and 1.94 s mean, so it offers no clear advantage over 8-bit beyond 6.3 MB less storage.

### Compatibility evidence

- The [pinned ONNX model card](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/blob/1939ad2a8e416c0acfeecc08a694d14ef25f2231/README.md) explicitly lists all eight artifacts as alternatives using the same `input_ids`, 256-float `style`, and `speed` inputs, and the same `waveform` output. It also publishes the sizes, voice samples, and a 510-token content limit.
- The [pinned Babylon source](https://github.com/Mobile-Artificial-Intelligence/babylon/blob/208e3d3d0d8305bb7c9ffa7d16a0c889cd0d2cae/src/lib/voice.cpp#L588-L690) loads any of those ONNX graphs through the same `Kokoro::Session` and reads a 256-float style row from the selected voice file. The repository’s [pinned README](https://github.com/Mobile-Artificial-Intelligence/babylon/blob/208e3d3d0d8305bb7c9ffa7d16a0c889cd0d2cae/README.md#c-api) itself demonstrates a quantized Kokoro model.
- Local verification downloaded FP16, q8f16, and 8-bit from the same pinned revision, matched their Hugging Face LFS SHA-256 values, and ran them plus the existing FP32 artifact through the exact pinned Babylon binary, Open Phonemizer, dictionary, and `en-US-heart.bin`. Every variant produced valid mono 16-bit 24 kHz WAV through both the CLI and HTTP server.
- All 54 bundled Babylon Kokoro voices are identically shaped 522,240-byte float files, matching the style-row contract. They cover eight languages across nine locales: German, Greek, English (UK/US), French, Italian, Japanese, Brazilian Portuguese, and Chinese. Model precision does not change voices or languages; the shared phonemizer/dictionary does. One representative voice was executed, while the uniform format and shared model interface establish structural compatibility for the rest.

### Quality, memory, and distribution limits

- Upstream says Kokoro is “resilient to quantization” and provides listening samples, but publishes no MOS or other objective per-artifact quality scores. Therefore “Best quality” for FP32 is the safe unquantized baseline; do not promise a quantified quality gap. A product listening test remains necessary before stronger wording.
- The RSS figures above are observations on one 24 GB M4 Mac, not minimum RAM requirements. No primary source specifies minimum system memory for these artifacts, so do not disable profiles using invented 8/16/24 GB thresholds. Show relative memory labels; exact hardware gates remain unknown.
- The [ONNX snapshot declares Apache-2.0](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/blob/1939ad2a8e416c0acfeecc08a694d14ef25f2231/README.md) and the [base Kokoro model](https://huggingface.co/hexgrad/Kokoro-82M) says its weights are Apache-licensed and suitable for production deployment. Babylon is [MIT licensed](https://github.com/Mobile-Artificial-Intelligence/babylon/blob/208e3d3d0d8305bb7c9ffa7d16a0c889cd0d2cae/LICENSE). Bundling is therefore technically and permissively licensed, provided the app ships the required Apache and MIT notices. The pinned ONNX snapshot has license metadata but no standalone `LICENSE` file, so packaging must source and retain an Apache-2.0 notice explicitly.
- Authoritative artifact metadata and content hashes are available from Hugging Face’s [immutable pinned tree API](https://huggingface.co/api/models/onnx-community/Kokoro-82M-v1.0-ONNX/tree/1939ad2a8e416c0acfeecc08a694d14ef25f2231/onnx?recursive=true&expand=true); pin direct resolve URLs to that same revision and verify those SHA-256 values before installation.

### Explicit unknowns

- Perceptual quality differences across all eight artifacts and all languages have not been objectively measured.
- Performance and peak memory on other supported Apple-silicon generations are unknown; current measurements are directional only.
- A defensible minimum-RAM threshold is unknown.
