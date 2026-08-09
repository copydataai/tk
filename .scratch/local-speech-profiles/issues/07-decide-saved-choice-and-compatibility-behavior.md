# Decide saved choice and compatibility behavior

Type: grilling
Status: resolved
Blocked by: 03, 04
Parent: [Make local speech profiles understandable and selectable](../map.md)

## Question

How should tk preserve or migrate saved Dictation profile, Reading profile, language, and Voice choices when an artifact is missing, removed, incompatible with the Mac, or changed by an app update, without silently changing the user's intended quality?

## Answer

Persist each choice independently and preserve intent rather than forcing the app into a runnable combination. An unavailable choice remains selected until the person explicitly changes it; tk blocks the affected request and never substitutes another profile, Dictation language, or Voice.

### Saved identities and first migration

- Save profiles by stable, semantic IDs that do not contain a filename, model version, or display label: `dictation.fast`, `dictation.balanced`, `dictation.best-quality`, `reading.lower-memory`, and `reading.best-quality`.
- Keep the existing `transcriptionLanguageCode` and `kokoroVoiceIdentifier` values as independent choices. Profile changes, downloads, repairs, removals, and app updates do not rewrite either one.
- On the first release with profile selection, an absent Dictation profile key becomes `dictation.balanced` and an absent Reading profile key becomes `reading.best-quality`. These are the models tk uses today, so existing and new installations keep current behavior.
- An absent Dictation language remains Auto; an absent Voice becomes `en-US-heart`, matching today's defaults.
- Treat an empty, non-string, or syntactically invalid saved value as corrupt and replace only that value with its default. Preserve a well-formed but unknown ID because it may belong to a newer app version or a temporarily retired catalog entry.
- Use explicit alias tables only for a renamed ID that is known to mean the same choice. Do not infer migrations from filenames or labels, and do not map a retired choice to the “closest” quality.

Each release's fixed manifest must retain a tombstone for any formerly shipped profile ID, with its kind, last user-facing name, unavailability reason, and any replacement action. This lets an update or downgrade explain a saved choice it cannot offer without pretending another profile is selected.

### Reconciliation and compatibility

Reconcile saved choices against the signed, release-fixed manifest at launch, after a download or removal, and immediately before each request. Reconciliation computes availability; it does not mutate a valid saved choice.

A profile is available only when its manifest entry supports the current OS, architecture, and bundled runtime and its required artifact is present and trusted under the lifecycle in [Decide the profile download and file lifecycle](06-decide-profile-file-lifecycle.md). The Low, Moderate, and High memory labels are guidance, not compatibility gates; an inference load failure must not create a guessed permanent RAM exclusion.

Use these outcomes:

| Condition | Saved choice | Behavior and action |
| --- | --- | --- |
| Bundled default replaced by an app update | Keep the same profile ID | Use the newly signed artifact on the next request. Artifact versions may change without changing the selected quality. |
| Optional artifact still matches the new manifest | Keep the same profile ID | Reuse it after verification. |
| Optional artifact is missing, manually deleted, corrupt, or no longer matches | Keep the same profile ID, marked **Selected · Unavailable** | Do not run; offer Download, Repair download, or Remove as applicable. Downloading or repairing restores availability but does not change any saved choice. |
| Profile is incompatible with this Mac or this app's runtime | Keep the same profile ID, marked **Selected · Unavailable** | Do not run or download it; explain the verified incompatibility and offer an explicit compatible choice. |
| Profile was retired or is known only to a newer app | Keep the raw ID and show its tombstone or a generic saved-by-newer-version row | Do not run; offer an explicit available choice. Never select a replacement automatically. |
| Optional selected profile is removed through tk | First require **Switch to [bundled default] and remove** | That confirmation is the explicit profile change; keep Dictation language and Voice unchanged. |
| Load or inference fails despite passing preflight | Keep the same profile ID | Fail that request, show the cause, and offer Retry, Repair download, or Choose another profile. Do not retry with another profile. |

Known incompatibility disables selecting or downloading that profile for a new choice. A previously saved choice can still appear selected and unavailable so tk does not erase intent.

### Dictation language and Voice

- All three current Dictation profiles share the same language behavior, so switching among them preserves Auto or the chosen language unchanged. Validate the saved language against the selected profile at request time. If a future profile cannot use it, retain both choices, mark the combination unavailable, and require an explicit language or profile choice; never silently switch to Auto.
- Both current Reading profiles share the same Voice files, so switching Reading quality preserves Voice unchanged. If a Voice is missing, retired, or incompatible, retain its identifier, block Read and Preview, and offer Repair or an explicit Voice choice. Replace the current startup behavior that silently substitutes `en-US-heart` when a non-empty saved Voice is unavailable.
- The Reading screen's Language picker is a view of the selected Voice's locale, not a separately persisted choice. Choosing another Voice language is an explicit Voice change; it may select the first Voice in that locale because the person initiated that change.
- A semantics-preserving alias may migrate a renamed language code or Voice identifier. If equivalence is uncertain, keep it unavailable instead of guessing.

### Request boundary and runtime reuse

- Snapshot the selected profile and its dependent language or Voice when a request begins. A settings change does not alter an in-flight request and applies to the next one.
- Preflight Dictation before recording starts and recheck before transcription; preflight Reading before obtaining selected text or generating a preview. If availability changed, do not start inference and show the affected saved choice.
- Key each resident speech process by the selected artifact identity. Reuse it only for that identity; when the next request chooses another profile, stop the idle process and start the requested one. No app restart is required.
- Continue disabling removal while an artifact is serving a request, as decided in the lifecycle ticket.

In Settings, an unavailable saved row remains visibly selected, includes the reason and relevant action, and states that the last request did not run. Another row is never presented as selected until the person chooses it.
