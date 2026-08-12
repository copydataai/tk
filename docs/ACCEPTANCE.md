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
- [ ] Grant Accessibility access from System Settings and confirm readiness updates.
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
- [ ] Quit from the menu bar and confirm `tk`, `whisper-server`, and `babylon` processes exit.
- [ ] Relaunch after logout/login or a reboot and repeat one dictation and one read-aloud operation.

## Release decision

- [ ] All required rows in `docs/COMPATIBILITY.md` have a current result.
- [ ] Every failure has a linked issue, severity, reproduction steps, and release disposition.
- [ ] A second person has reviewed the checksum, notarization result, and completed record.
- [ ] Release owner decision: SHIP / HOLD

Notes and linked issues:

