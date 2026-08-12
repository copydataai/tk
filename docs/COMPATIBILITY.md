# Compatibility and hardening qualification matrix

`tk` requires macOS 14 or newer on Apple silicon. Qualify the exact installed DMG intended for publication. A row is evidence only when its `Record` links to a dated record for that DMG, hardware, operating-system build, device, and target. Automated tests may support a record, but may not turn a physical-device or DMG row into `Pass`.

The only permitted status values are `Pass`, `Fail`, `Blocked`, and `Not run`. Do not use blank, partial, assumed, inherited, or prose statuses. `Not run` is not evidence. A `Fail` record must link an issue and state the release owner's `SHIP` or `HOLD` decision. Never combine rows or generalize a result to another macOS version, target class, device route, interruption phase, or operation.

## DMG, clean-install, and offline matrix

Each row requires a clean macOS user account with no prior `tk` permission grants. Offline means networking is disconnected before first launch and remains disconnected through the operation.

| macOS | Qualification operation | Status | Record |
| --- | --- | --- | --- |
| 14.x latest | Downloaded DMG checksum, signature, notarization, mount, drag-install, Gatekeeper launch, version, menu item | Not run | |
| 14.x latest | Clean-install first launch, Microphone prompt, Accessibility denied, onboarding completes in Copy Mode | Not run | |
| 14.x latest | Clean-install offline Copy Mode record, local transcribe, pending-result relaunch, user-initiated Copy | Not run | |
| 14.x latest | Clean-install offline automatic insertion after Accessibility is granted | Not run | |
| 14.x latest | Clean-install offline Read Selection after Accessibility is granted | Not run | |
| 15.x latest | Downloaded DMG checksum, signature, notarization, mount, drag-install, Gatekeeper launch, version, menu item | Not run | |
| 15.x latest | Clean-install first launch, Microphone prompt, Accessibility denied, onboarding completes in Copy Mode | Not run | |
| 15.x latest | Clean-install offline Copy Mode record, local transcribe, pending-result relaunch, user-initiated Copy | Not run | |
| 15.x latest | Clean-install offline automatic insertion after Accessibility is granted | Not run | |
| 15.x latest | Clean-install offline Read Selection after Accessibility is granted | Not run | |
| 26.x latest | Downloaded DMG checksum, signature, notarization, mount, drag-install, Gatekeeper launch, version, menu item | Not run | |
| 26.x latest | Clean-install first launch, Microphone prompt, Accessibility denied, onboarding completes in Copy Mode | Not run | |
| 26.x latest | Clean-install offline Copy Mode record, local transcribe, pending-result relaunch, user-initiated Copy | Not run | |
| 26.x latest | Clean-install offline automatic insertion after Accessibility is granted | Not run | |
| 26.x latest | Clean-install offline Read Selection after Accessibility is granted | Not run | |

## Current-macOS target matrix

These rows represent every advertised target class on current macOS. Use the built-in microphone unless the row names another route. An insertion receipt must identify the operation and final disposition. Target refusal means a deliberately non-editable or otherwise refusing control fails explicitly without claiming insertion or overwriting the clipboard.

| macOS | Target class | Target app/control | Qualification operation | Status | Record |
| --- | --- | --- | --- | --- | --- |
| 26.x latest | Standard AppKit editor | TextEdit editable document | Automatic insertion preserves surrounding text and records an insertion receipt | Not run | |
| 26.x latest | Standard AppKit editor | TextEdit read-only document | Target refusal is explicit; no insertion success or destructive fallback is claimed | Not run | |
| 26.x latest | Standard AppKit editor | TextEdit selection | Read Selection speaks the selected text and restores the pre-existing clipboard | Not run | |
| 26.x latest | Browser text control | Safari editable text control | Automatic insertion preserves surrounding text and records an insertion receipt | Not run | |
| 26.x latest | Browser text control | Safari disabled or read-only control | Target refusal is explicit; no insertion success or destructive fallback is claimed | Not run | |
| 26.x latest | Browser text control | Safari selected page text | Read Selection speaks the selected text and restores the pre-existing clipboard | Not run | |
| 26.x latest | Apple productivity app | Notes editable note | Automatic insertion preserves surrounding text and records an insertion receipt | Not run | |
| 26.x latest | Apple productivity app | Notes non-editable target | Target refusal is explicit; no insertion success or destructive fallback is claimed | Not run | |
| 26.x latest | Apple productivity app | Notes selection | Read Selection speaks the selected text and restores the pre-existing clipboard | Not run | |
| 26.x latest | Apple productivity app | Mail message composer | Automatic insertion preserves surrounding text and records an insertion receipt | Not run | |
| 26.x latest | Apple productivity app | Mail non-editable message view | Target refusal is explicit; no insertion success or destructive fallback is claimed | Not run | |
| 26.x latest | Apple productivity app | Mail message selection | Read Selection speaks the selected text and restores the pre-existing clipboard | Not run | |
| 26.x latest | Third-party editor | Microsoft Word editable document | Automatic insertion preserves surrounding text and records an insertion receipt | Not run | |
| 26.x latest | Third-party editor | Microsoft Word protected or read-only document | Target refusal is explicit; no insertion success or destructive fallback is claimed | Not run | |
| 26.x latest | Third-party editor | Microsoft Word selection | Read Selection speaks the selected text and restores the pre-existing clipboard | Not run | |
| 26.x latest | AX-free Copy | TextEdit is frontmost; Accessibility denied | Record and local transcribe complete without focus capture, selected-text access, Accessibility API calls, or synthetic key events | Not run | |
| 26.x latest | AX-free Copy | TextEdit is frontmost; Accessibility denied | User-initiated Copy records `copyOnly`, retains pending text, and warns that other processes can read the clipboard | Not run | |

## Physical microphone and continuity matrix

These are physical gates. Run every row on a real device. A connection or interruption result for one route does not qualify another route. `Blocked` is appropriate only when the named condition cannot be produced safely or required hardware is unavailable, with the blocker linked in `Record`.

| macOS | Input route | Interruption phase | Qualification operation | Status | Record |
| --- | --- | --- | --- | --- | --- |
| 26.x latest | Built-in microphone | Recording | Sleep prepares the transaction, wake records `interruptedRecoverable`, partial capture is cleaned, and no completion is claimed | Not run | |
| 26.x latest | Built-in microphone | Local transcription | Sleep terminates the stale helper; wake reports preserved audio or explicit loss and offers a new-operation retry | Not run | |
| 26.x latest | Built-in microphone | After wake | Device reprobe completes and retry uses a new operation identifier | Not run | |
| 26.x latest | USB microphone | Recording | Sleep prepares the transaction, wake records `interruptedRecoverable`, partial capture is cleaned, and no completion is claimed | Not run | |
| 26.x latest | USB microphone | Local transcription | Sleep terminates the stale helper; wake reports preserved audio or explicit loss and offers a new-operation retry | Not run | |
| 26.x latest | USB microphone | After wake | Device reprobe completes and retry uses a new operation identifier | Not run | |
| 26.x latest | Bluetooth microphone | Recording | Sleep prepares the transaction, wake records `interruptedRecoverable`, partial capture is cleaned, and no completion is claimed | Not run | |
| 26.x latest | Bluetooth microphone | Local transcription | Sleep terminates the stale helper; wake reports preserved audio or explicit loss and offers a new-operation retry | Not run | |
| 26.x latest | Bluetooth microphone | After wake | Device reprobe completes and retry uses a new operation identifier | Not run | |
| 26.x latest | Built-in microphone | Recording | Active built-in route disappears; operation is interrupted and does not switch routes mid-transaction | Not run | |
| 26.x latest | USB microphone | Recording | Active USB microphone disconnects; operation is interrupted, capture is cleaned, and no built-in fallback occurs mid-transaction | Not run | |
| 26.x latest | USB microphone | Next operation | USB microphone reconnects; reprobe permits a new operation on the explicitly selected or fallback route | Not run | |
| 26.x latest | Bluetooth microphone | Recording | Active Bluetooth microphone disconnects; operation is interrupted, capture is cleaned, and no built-in fallback occurs mid-transaction | Not run | |
| 26.x latest | Bluetooth microphone | Next operation | Bluetooth microphone reconnects; reprobe permits a new operation on the explicitly selected or fallback route | Not run | |
| 26.x latest | Built-in microphone active; USB connects | Recording | Non-active USB connection does not change the active route mid-transaction | Not run | |
| 26.x latest | Built-in microphone active; Bluetooth connects | Recording | Non-active Bluetooth connection does not change the active route mid-transaction | Not run | |

## Resource-pressure matrix

| macOS | Resource condition | Qualification operation | Status | Record |
| --- | --- | --- | --- | --- |
| 26.x latest | Warning memory pressure | Active local transcription continues as `degraded` without changing the selected Dictation profile | Not run | |
| 26.x latest | Critical memory pressure | New or active local transcription is `resourceBlocked`; audio is preserved when available or loss is explicit | Not run | |
| 26.x latest | Warning thermal pressure | Active local transcription continues as `degraded` without changing the selected Dictation profile | Not run | |
| 26.x latest | Critical thermal pressure | New or active local transcription is `resourceBlocked`; audio is preserved when available or loss is explicit | Not run | |

## Helper lifecycle and local inference boundary matrix

Each operation gets a fresh `whisper-cli`. No row may be satisfied by observing a different operation. The packaged application must not contain or launch `whisper-server`.

| Operation | Qualification operation | Status | Record |
| --- | --- | --- | --- |
| Dictation A | No resident listener exists before launch; one operation-scoped `whisper-cli` starts | Not run | |
| Dictation A | Malformed input is rejected before helper launch | Not run | |
| Dictation B | Oversize input is rejected before helper launch | Not run | |
| Dictation C | Over-duration input is rejected before helper launch | Not run | |
| Dictation D | Concurrent request is rejected while another operation owns the helper boundary | Not run | |
| Dictation E | Helper crash produces an explicit failure and removes the operation output and audio directories | Not run | |
| Dictation F | Helper timeout terminates the helper and removes the operation output and audio directories | Not run | |
| Dictation G | Cancellation terminates the helper and removes the operation output and audio directories | Not run | |
| Relaunch cleanup A | Stale tk-owned helper record and operation directory are removed without following symlinks | Not run | |
| Relaunch cleanup B | Fresh tk-owned operation directory is retained | Not run | |
| Relaunch cleanup C | Verified-live tk-owned operation directory is retained | Not run | |
| Relaunch cleanup D | Unrelated, malformed, and symlinked directories are retained and paths outside `tk-audio` are untouched | Not run | |
| Packaged DMG | `whisper-cli` is present and `whisper-server` is absent | Not run | |
| Dictation H | No-listener framing: completion proves an operation-scoped helper result, not access to a resident listener | Not run | |
| Dictation I | Legacy unauthenticated-listener framing: no reusable HTTP authority, token, port, or helper process remains after exit | Not run | |

## Retention and deletion matrix

| Scope | Qualification operation | Status | Record |
| --- | --- | --- | --- |
| Retention zero | Completed dictation creates no history row | Not run | |
| Retention zero | Separately pending recovery result survives until explicitly discarded or selected by Clear All | Not run | |
| Clear All: transcript store | Database rows, WAL, and shared-memory state are attempted and individually listed in the deletion receipt | Not run | |
| Clear All: selected app artifacts | Pending artifact and selected corrupt archives are attempted and individually listed in the deletion receipt | Not run | |
| Clear All: exclusions | SSD remanence, snapshots, backups, and free space are listed as exclusions without a secure-erasure claim | Not run | |
| Relaunch after Clear All | Selected application-controlled transcript and pending artifacts remain absent | Not run | |

## Compatibility record template

Copy this section for exactly one matrix row. Do not use one record to qualify multiple rows.

### `<tag> / <matrix section> / <row operation>`

- Date and tester:
- Release tag:
- DMG filename and SHA256:
- Mac model, chip, and memory:
- macOS version and build:
- Input device, connection, and sample rate:
- Target app, version, and control:
- Clean install or upgrade:
- Accessibility state:
- Microphone state:
- Network state:
- Operation identifier:
- Status: Pass / Fail / Blocked / Not run
- Evidence links:
- Exact observations:
- Failure issue, severity, and reproduction steps:
- Release disposition for failure: SHIP / HOLD
- Blocker and owner:

## Release decision

Every required row must have a current linked record. Every `Fail` must link an issue with severity, reproduction steps, and an explicit `SHIP` or `HOLD` disposition. `Blocked` rows require an owned blocker and release disposition. `Not run` rows are unqualified and are not evidence for shipping.
