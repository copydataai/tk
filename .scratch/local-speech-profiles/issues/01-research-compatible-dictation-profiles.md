# Research compatible Dictation profiles

Type: research
Status: resolved
Blocked by:
Parent: [Make local speech profiles understandable and selectable](../map.md)

## Question

Which pinned Whisper model artifacts can the existing `whisper.cpp` v1.9.1 Metal runtime load without architectural changes, and what verified facts support a small Fast/Balanced/Best candidate set: download size, quantization, multilingual capability, expected quality tradeoff, realistic memory requirement, license, checksum source, and distribution suitability?

## Answer

Recommend these three multilingual GGML artifacts from one pinned conversion-repository revision:

| Profile candidate | Artifact | Exact download | SHA-256 | Honest user-facing memory label | Quality/speed basis |
| --- | --- | ---: | --- | --- | --- |
| Fast | [`ggml-small-q5_1.bin`](https://huggingface.co/ggerganov/whisper.cpp/blob/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small-q5_1.bin) | 190,085,487 bytes (181.3 MiB) | `ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb` | Low | 244M-parameter `small`; materially smaller and expected to trade recognition quality for speed versus the large-family choices. |
| Balanced (current/default) | [`ggml-large-v3-turbo-q5_0.bin`](https://huggingface.co/ggerganov/whisper.cpp/blob/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin) | 574,041,195 bytes (547.4 MiB) | `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` | Moderate | 809M-parameter large-v3 derivative with decoder layers pruned from 32 to 4; upstream describes it as much faster with minor quality degradation. This preserves today's behavior. |
| Best quality | [`ggml-large-v3-q5_0.bin`](https://huggingface.co/ggerganov/whisper.cpp/blob/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-q5_0.bin) | 1,081,140,203 bytes (1.007 GiB) | `d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1` | High | Full 1,550M-parameter large-v3 architecture; avoids turbo's documented pruning tradeoff but should be slower. |

The exact sizes and SHA-256 values come from the Hugging Face LFS metadata at pinned repository revision [`5359861c…`](https://huggingface.co/api/models/ggerganov/whisper.cpp/revision/5359861c739e955e79d9a303bcbc70fb988958b1?blobs=true), not the short SHA column in the model README. Pin the revision in download URLs and verify these SHA-256 values before installation.

### Compatibility and behavior

- The checked-out runtime is exactly `whisper.cpp` `v1.9.1`. Its own [`download-ggml-model.sh`](https://github.com/ggml-org/whisper.cpp/blob/v1.9.1/models/download-ggml-model.sh) lists all three model names, and v1.9.1 documents GGML loading, Metal on Apple Silicon, integer quantization, and multilingual naming in its [model documentation](https://github.com/ggml-org/whisper.cpp/blob/v1.9.1/models/README.md). No inference-engine or audio-pipeline change is required; product code must only replace the currently hard-coded model filename and restart the resident server when selection changes.
- All three names omit `.en`, so they are multilingual. OpenAI describes Whisper as supporting multilingual recognition and language identification; its current [model table](https://github.com/openai/whisper/blob/main/README.md#available-models-and-languages) lists `small`, `turbo`, and `large` as multilingual. The app's existing Auto and explicit-language request flow can remain unchanged.
- Q5 quantization reduces disk and memory use and can improve speed, but `whisper.cpp` explicitly does **not** quantify the resulting recognition-quality loss. Therefore the UI should not promise percentages or claim the Q5 full large-v3 artifact is the absolute highest possible quality—only the best of this deliberately small, practical set. See the project's [quantization documentation](https://github.com/ggml-org/whisper.cpp/tree/v1.9.1#quantization) and [quantization release note](https://github.com/ggml-org/whisper.cpp/discussions/838).
- OpenAI's [large-v3-turbo model card](https://huggingface.co/openai/whisper-large-v3-turbo) supports the Balanced tradeoff: 4 decoder layers instead of 32, much faster, with minor quality degradation. It also warns that accuracy varies by language, accent, and dialect and that Whisper can hallucinate or repeat text; profiles cannot remove those limits.

### Memory and availability

Do not present an exact minimum-RAM requirement yet. `whisper.cpp` documents about 852 MB for unquantized `small` and about 3.9 GB for unquantized `large`, then only states that quantized models use less memory; it publishes no v1.9.1 Q5 totals for these three artifacts. OpenAI's VRAM figures are for its PyTorch runtime and are not valid compatibility thresholds for this Metal application.

One local sanity run of the current pinned Q5 turbo artifact with the repo's exact v1.9.1 Metal binary on an Apple M4/24 GB Mac transcribed the bundled 11-second sample successfully and measured 828,964,864 bytes maximum RSS (`/usr/bin/time -l`). That supports “Moderate,” but it is one machine, not a minimum requirement. Use Low/Moderate/High in the initial UI; add numeric requirements only after measuring all three artifacts on the oldest supported 8 GB/16 GB Apple-silicon machines. Free-space checks can be exact from the download sizes now.

### License and distribution

OpenAI states that Whisper code and model weights are [MIT licensed](https://github.com/openai/whisper/blob/main/README.md#license), and the [GGML conversion repository](https://huggingface.co/ggerganov/whisper.cpp) is marked MIT. These pinned, checksum-verified files are technically suitable for optional local distribution/download with the applicable MIT notice and source attribution.

Explicit unknown: the separate Hugging Face card for `openai/whisper-large-v3` is marked Apache-2.0 while OpenAI's canonical repository says all model weights are MIT. This metadata mismatch should be clarified before shipping the Best artifact if release counsel requires a single unambiguous provenance record; it does not affect runtime compatibility.
