# Decide the Dictation profile portfolio

Type: grilling
Status: resolved
Blocked by: 01
Parent: [Make local speech profiles understandable and selectable](../map.md)

## Question

Which researched Dictation profiles should tk offer, what non-technical names and “Best for” descriptions should each use, which remains the default, and what verified storage or memory conditions make each available, warned, or disabled?

## Answer

Offer three Dictation profiles:

| Dictation quality | Technical detail | Best for | Download | Memory guidance | Delivery |
| --- | --- | --- | ---: | --- | --- |
| **Fast** | Whisper small Q5 | Quick notes when speed and lower resource use matter more than catching every word | 181.3 MiB | Low | Optional explicit download |
| **Balanced — Recommended** | Whisper large-v3-turbo Q5 | Everyday dictation with a strong balance of speed and accuracy | 547.4 MiB | Moderate | Current bundled default; preserves existing behavior |
| **Best quality** | Whisper large-v3 Q5 | Dictation where the best accuracy offered by tk matters more than waiting and resource use | 1.007 GiB | High | Optional explicit download |

The primary selector shows the bold names, “Best for” sentence, exact download size, relative memory label, and installed/download state. Artifact names, quantization, hashes, and licenses belong behind technical details.

All three retain the same language selector, automatic language detection, local-only processing, Silero VAD, and post-recording rather than live transcription. A nearby common-limits note must say plainly that recognition can miss, repeat, or invent words and that results vary with language, accent, background noise, and microphone quality. Do not imply that any profile guarantees accuracy.

**Default:** Balanced remains selected for current and new users because it is today's behavior. Installing another profile does not select it; selection is a deliberate second action and takes effect on the next dictation.

**Availability:**

- Calculate storage eligibility from the exact artifact size plus the temporary space required for an atomic download. Disable Download only when verified free space is insufficient, and state the required space plainly.
- Do not invent numeric minimum-RAM requirements or disable a profile based on total system memory yet. The available evidence covers only one M4/24 GB machine. Show Low, Moderate, or High memory guidance; show a caution on Best quality, then handle an actual load failure explicitly without silent fallback.
- The Best quality artifact may be used for development, but release distribution waits for the profile file-lifecycle decision to settle the conflicting upstream license metadata and required notices.
- Every download uses the immutable revision and SHA-256 recorded in [Research compatible Dictation profiles](01-research-compatible-dictation-profiles.md).

This decision intentionally avoids a hardware compatibility promise that the evidence cannot support. Numeric RAM gates can be added only after measurements cover the oldest supported Apple-silicon memory tiers.
