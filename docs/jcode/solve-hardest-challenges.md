# J-Code implementation packet — solve tk's hardest challenges

You are the managed J-Code implementer inside `/Users/josesanchez/Developer/public/tk-jcode-challenges-2026-08-12` on branch `feat/solve-hardest-challenges`. Do not launch J-Code, Codex, or any nested agent. Work autonomously. Inspect `CONTEXT.md`, `README.md`, `docs/ACCEPTANCE.md`, `docs/COMPATIBILITY.md`, current implementation, tests, packaging scripts, and entitlements before editing.

## Objective

Resolve every software-addressable gap behind tk's hardest challenges. Do not claim source code can guarantee behavior of arbitrary future macOS applications, physical microphones, OS releases, hardware pressure, secure erasure, model accuracy, signing/notarization credentials, or human acceptance. For external boundaries, implement executable evidence collection and fail-closed release qualification—not prose-only checklists.

## Required packets and exact micro-commits

Complete in order. For each packet: add a failing test through a public seam, implement the smallest deep module, run focused checks, and make exactly one focused commit using the specified message. No unrelated cleanup.

### T1 — destination transaction integrity
Commit: `feat: deepen transactional text insertion`

Strengthen the current dictation transaction and insertion receipts for heterogeneous targets.

Required behavior:
- Capture a stable destination fingerprint immediately before commit and re-check it immediately before mutation.
- Refuse secure fields, protected/read-only/disabled controls, changed focus/selection, and ambiguous target identity.
- Prefer direct AX range mutation when safely available; isolate pasteboard/synthetic-paste fallback as a separately classified adapter.
- Preserve surrounding text and selection, including Unicode/emoji/grapheme boundaries.
- Verify readable post-state; never label an unreadable post-state verified.
- Persist candidate text before any destination mutation and keep it through every nonverified result.
- Make retry idempotent and linked to the original operation; narrowly targeted undo only when exact target/content state still matches.
- Add adapter-contract tests plus real-system smoke hooks that remain explicit opt-in.

### T2 — durable crash recovery and progressive commitment
Commit: `feat: persist progressive dictation commitments`

Implement a durable, versioned operation journal spanning capture, inference, pending result, destination choice, insertion attempt, verification, retry, copy, discard, and commit.

Required behavior:
- Atomic transition persistence with operation ID, predecessor/version, content digest, retention disposition, destination fingerprint where applicable, and bounded reason codes.
- Recover deterministically after process death at every transition; corrupt or future-version journals fail recoverably without deleting evidence.
- Repeated recovery/retry is idempotent and cannot duplicate verified insertion.
- Support targetless capture: preserve recognized text before a destination is chosen.
- Preserve user-visible text while keeping diagnostics content-free.
- Explicitly separate temporary audio retention, pending text retention, history retention, and clipboard exposure.

### T3 — bounded-latency inference admission
Commit: `feat: enforce dictation performance budgets`

Turn declared performance budgets into measured runtime enforcement and evidence.

Required behavior:
- Preflight duration, audio bytes/format, available memory/pressure, helper availability, profile resource estimate, and concurrency before launch.
- Capture cold/warm startup, inference duration, peak memory when observable, termination reason, and cleanup result in a content-free receipt.
- Enforce bounded timeout and response sizes; kill the full operation process group and clean artifacts.
- Do not silently switch model/profile/device after user selection. Return a recoverable typed outcome when the selected profile cannot run.
- Add deterministic fake-helper tests and a real bundled-helper benchmark command/harness whose heavy execution is opt-in.
- Release policy must use explicit per-hardware thresholds rather than one universal promise.

### T4 — microphone and OS continuity evidence
Commit: `feat: record physical continuity evidence`

Create executable qualification support for the existing physical matrix.

Required behavior:
- An evidence recorder binds exact app build/DMG digest, macOS build, hardware, input route/device UID, sample rate, operation ID, interruption phase, notifications observed, outcome, audio disposition, helper disposition, and tester assertion.
- It must not self-promote simulated events to physical `Pass`.
- Provide a guided CLI/script or in-app debug workflow to run one named matrix row and atomically write a dated machine-readable record.
- Validate that one record maps to exactly one current matrix row and reject stale app/OS/device mismatches, missing observations, or generalized evidence.
- Add an aggregator that updates/reports matrix status from validated records without turning `Not run` into evidence.
- Unit tests use synthetic records but label them simulated/ineligible for physical release status.

### T5 — least-privilege capability enforcement
Commit: `feat: enforce least-privilege speech capabilities`

Deepen capability-specific permission and privacy enforcement.

Required behavior:
- Copy Mode never invokes Accessibility, captures selection/focus, or sends synthetic events.
- Automatic insertion and Read Selection request only their required capabilities at operation time.
- Secure-field refusal is explicit and recoverable.
- Clipboard fallback records exposure and restores prior contents only when tk still owns the temporary value; never overwrite another process's change.
- Diagnostics and deletion receipts remain content-free and path-sanitized.
- App entitlements, helper lifecycle, network declarations, and operation-scoped authority are validated by an executable release audit.
- Add regression tests that instrument capability adapters and prove forbidden calls are zero.

### T6 — installed-artifact release qualification
Commit: `feat: automate installed app qualification`

Make the DMG/installed-app release boundary executable and fail closed.

Required behavior:
- Deterministic release script that builds the app, verifies bundled model/helper hashes, checks `whisper-cli` present and `whisper-server` absent, inspects entitlements, signs/notarizes when credentials are explicitly supplied, builds DMG, emits checksums/SBOM/provenance, and never logs secrets.
- Without signing credentials, produce an explicitly unsigned development artifact that cannot satisfy release status.
- Clean-install/offline qualification runner validates mounted artifact, drag-installed app, Gatekeeper/signature/notarization status, version, menu launch readiness hooks, no required model download, no resident listener, expected network policy, uninstall/rollback metadata, and bundled-license inventory.
- Convert `docs/COMPATIBILITY.md` into or pair it with a machine-validated record source; release gate fails if any required row is `Not run`, `Fail`, stale, malformed, or unsupported by a linked record.
- Do not fabricate physical app/microphone evidence. Leave those rows blocked until real execution records exist.
- Resolve the previously observed Babylon dependency/package stall if reproducible, using pinned dependencies/caches or a deterministic vendoring/build strategy with license compliance.

## Cross-cutting acceptance

- Preserve macOS 14+ Apple-silicon support and existing user-facing behavior unless fail-closed strengthening is required.
- Use public state-machine, adapter, script, and CLI seams for tests; avoid tests tied to private implementation details.
- No transcript/audio content, credentials, raw private paths, or selected text in diagnostics/evidence by default.
- Update docs honestly using Implemented / Requires physical qualification / Not enforceable classifications.
- Run focused tests and `git diff --check` after every packet.
- Final gates:
  - `swift test`
  - warnings-as-errors build
  - shell syntax and packaging-script checks
  - entitlements and bundled-artifact audits
  - development app/DMG build if possible
  - all new qualification/audit command smokes
  - `git diff --check`
- Leave the worktree clean with the six exact commits above following the pre-existing prompt commit.
- Final response must list commit SHAs, exact check results, skips, and every physical/signing/notarization/app-matrix row still requiring external execution. Never call `Not run` a pass.
