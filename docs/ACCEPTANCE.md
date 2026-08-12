# Release acceptance

Run this checklist against the exact DMG intended for publication. Use a macOS user account that has not previously granted `tk` permissions when checking first-run behavior. Record the result in the release issue or pull request and attach logs or screen recordings for failures.

## Test record

- Version/tag:
- DMG filename and SHA256:
- Tester and date:
- Mac model, chip, memory:
- macOS version and build:
- Input device:
- Target apps and versions:
- Network state during offline checks:
- Result: PASS / FAIL

## Artifact and installation

- [ ] Download both the DMG and `.sha256` file from the GitHub release.
- [ ] Run `shasum -a 256 -c tk-<version>.dmg.sha256` and confirm it reports `OK`.
- [ ] Run `spctl --assess --type open --context context:primary-signature --verbose=2 tk-<version>.dmg` and confirm acceptance.
- [ ] Mount the DMG, drag `tk` to Applications, eject the DMG, and open the installed copy.
- [ ] Confirm Gatekeeper opens the app without an unidentified-developer warning.
- [ ] Confirm the displayed app version matches the release tag.
- [ ] Confirm the menu bar item appears and the main window can be reopened from it.

## First run and permissions

- [ ] Confirm onboarding clearly reports Microphone and Accessibility readiness.
- [ ] Grant Microphone access from the app prompt and confirm readiness updates.
- [ ] With Accessibility denied and Microphone granted, confirm onboarding can complete in Copy Mode.
- [ ] Complete a Copy Mode dictation and confirm it reaches a ready result with pending text persisted across relaunch.
- [ ] Confirm Copy Mode does not capture focus, access selected text, call Accessibility APIs for dictation, or post synthetic key events.
- [ ] Choose **Copy** and confirm the app reports a `copyOnly` disposition while keeping the text pending. Confirm the UI warns that other processes can read clipboard contents.
- [ ] Confirm retry/automatic insertion is disabled until Accessibility is granted.
- [ ] Grant Accessibility access from System Settings and confirm readiness updates.
- [ ] Confirm automatic insertion becomes available after Accessibility is granted.
- [ ] Revoke Accessibility and confirm Read Selection remains unavailable and explains that permission is required.
- [ ] Quit and reopen `tk`; confirm both permissions remain recognized.
- [ ] Deny or revoke each permission in turn and confirm the app explains what is unavailable without crashing.

## Dictation in real apps

Repeat the following in every target app listed in the compatibility record:

- [ ] Place the insertion point in an editable text field containing existing text.
- [ ] Start dictation with the configured global shortcut, speak a short sentence, and stop with the shortcut.
- [ ] Confirm the transcript is inserted at the insertion point and surrounding text is preserved.
- [ ] Confirm punctuation and non-English speech appropriate to the test are usable.
- [ ] Confirm cancelling or producing silence does not insert stray text.
- [ ] Confirm a completed dictation appears in History with the expected text and timestamp.
- [ ] Switch to another connected microphone and confirm recording uses the selected or fallback input.

## Read aloud in real apps

Repeat the following in every target app listed in the compatibility record:

- [ ] Select text, invoke the read-selection shortcut, and confirm audible speech matches the selection.
- [ ] Confirm the pre-existing clipboard contents are unchanged after reading.
- [ ] Preview at least one voice from the app and confirm speed and volume changes take effect.
- [ ] Stop playback and confirm it ends promptly without leaving a helper process running.
- [ ] Try an empty selection and confirm the app handles it without crashing or reading unrelated text.

## Privacy, offline behavior, and lifecycle

- [ ] Disconnect networking, relaunch the installed app, and complete dictation and read-aloud successfully using bundled defaults.
- [ ] Confirm no model download or account sign-in is requested for bundled defaults.
- [ ] Confirm microphone audio is not retained after dictation.
- [ ] Confirm local history persists after relaunch and can be cleared through the app.
- [ ] Export History and confirm every record includes `contentTrust: untrustedSpeechRecognition`, `agentEligibility: ineligible`, an optional `sourceOperationID`, and `retentionDisposition: retainedHistory`.
- [ ] Open a database created by the prior release and confirm legacy rows receive the same safe trust and agent-eligibility defaults.
- [ ] Set history retention to zero while a recovery result is pending; confirm history remains empty and the separately pending result survives.
- [ ] Use **Clear All** and confirm the deletion receipt lists the transcript database, WAL, shared-memory state, selected corrupt archives, and pending artifact as successes or failures, plus SSD, snapshots, backups, and free-space exclusions.
- [ ] Confirm **Clear All** removes selected application-controlled pending/corrupt artifacts and leaves no claim that SSD blocks were securely erased.
- [ ] During dictation, confirm `whisper-cli` exists only for that operation and exits on completion or cancellation. Confirm no `whisper-server` listener remains.
- [ ] Quit from the menu bar and confirm `tk`, `whisper-cli`, and `babylon` processes exit.
- [ ] Relaunch after logout/login or a reboot and repeat one dictation and one read-aloud operation.

### Local inference boundary

The pinned whisper.cpp server does not provide narrow, distributable request authentication or request-size enforcement. tk therefore packages `whisper-cli` and launches a fresh helper for each dictation instead of exposing a reusable HTTP listener. Input size and declared duration are checked before launch. Only one operation is admitted at a time. Runtime, response size, and operation lifetime are bounded, and cancellation kills the helper and removes its private output directory. Standard output and standard error are discarded so helper diagnostics cannot disclose request authority. There is no reusable token or process authority after exit.

- [ ] Confirm malformed, oversize, and over-duration inputs are rejected before `whisper-cli` starts.
- [ ] Confirm a second concurrent dictation is rejected while the first helper is active.
- [ ] Confirm timeout and cancellation terminate the helper and remove its operation directory.
- [ ] Confirm the packaged app contains `whisper-cli` and does not contain `whisper-server`.

This boundary protects against unrelated local processes reaching an unauthenticated resident inference listener. Compromise of the same user account or the full system remains out of scope because such an attacker can inspect or control tk's files and processes directly.

## Release decision

- [ ] All required rows in `docs/COMPATIBILITY.md` have a current result.
- [ ] Every failure has a linked issue, severity, reproduction steps, and release disposition.
- [ ] A second person has reviewed the checksum, notarization result, and completed record.
- [ ] Release owner decision: SHIP / HOLD

Notes and linked issues:
