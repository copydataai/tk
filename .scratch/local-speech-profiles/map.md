# Make local speech profiles understandable and selectable

Label: wayfinder:map

## Destination

A decision-complete specification for separate Dictation and Reading profiles that lets non-technical users choose among compatible local models, understand their practical limits, and manage optional downloads without weakening tk's offline privacy promise or changing existing defaults unexpectedly.

## Notes

- Domain: local speech tools; use the vocabulary in [`CONTEXT.md`](../../CONTEXT.md).
- Every session should consult the `wayfinder`, `grilling`, and `domain-modeling` skills; prototype tickets should also use `prototype`.
- Preserve the current Whisper large-v3-turbo Q5 and Kokoro FP32 behavior until the user deliberately selects another profile.
- Use “Dictation quality” and “Reading quality” in the interface. Technical model names are secondary details.
- Alternative profiles require an explicit Download action and take effect on the next request without restarting.
- Inference remains local. Never silently fall back after a load or compatibility failure.
- Show verified exact download sizes and memory requirements; otherwise use honest relative guidance rather than invented precision.
- Planning only: this map resolves decisions and hands off a specification; it does not implement the feature.

## Decisions so far

- [Research compatible Dictation profiles](issues/01-research-compatible-dictation-profiles.md) — The existing runtime supports a practical three-profile set: small Q5 for speed, today's turbo Q5 as the balanced default, and large-v3 Q5 for best quality; exact RAM gates remain unverified.
- [Research compatible Reading profiles](issues/02-research-compatible-reading-profiles.md) — Offer the current FP32 model for best quality and consider 8-bit specifically for lower storage and memory; it was slower in local testing, while FP16 and q8f16 add no useful tier.
- [Decide the Dictation profile portfolio](issues/03-decide-dictation-profile-portfolio.md) — Offer Fast, Balanced (the current recommended default), and Best quality with exact storage checks and relative memory guidance; do not invent numeric RAM gates.
- [Decide the Reading profile portfolio](issues/04-decide-reading-profile-portfolio.md) — Offer Lower memory and Best quality (the current recommended default); the smaller model can begin reading more slowly, and Voice remains an independent, compatible choice.
- [Prototype understandable Speech profile settings](issues/05-prototype-profile-settings.md) — Use a focused Speech profiles destination in the existing Settings sidebar, with vertical native choices and inline lifecycle states, limits, and technical disclosure.
- [Decide the profile download and file lifecycle](issues/06-decide-profile-file-lifecycle.md) — Extend the existing pinned, checksummed, atomic model flow into explicit resumable downloads; bundle immutable defaults, preserve partials safely, require deliberate selection/removal, and never fall back silently.
- [Decide saved choice and compatibility behavior](issues/07-decide-saved-choice-and-compatibility-behavior.md) — Persist stable independent choices, retain unavailable intent across updates and failures, and block requests instead of silently substituting a profile, language, or Voice.
- [Approve the Speech profile experience contract](issues/08-approve-the-profile-experience-contract.md) — Approved the decision-complete [implementation and acceptance contract](implementation-contract.md), consolidating exact manifest, UX, lifecycle, compatibility, accessibility, privacy, release, and validation requirements.

The Wayfinder destination is reached. The approved contract is ready for implementation planning.

## Not yet specified

None.

## Out of scope

- Cloud inference or cloud fallback.
- Custom model imports.
- Live or streaming dictation.
- On-device performance benchmarking.
- A live remote model catalog or automatic model updates outside app releases.
